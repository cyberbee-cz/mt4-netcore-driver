//+------------------------------------------------------------------+
//|                                                 FileExporter.mq4 |
//|                                      Copyright 2020, cyberbee.cz |
//|                                          https://www.cyberbee.cz |
//+------------------------------------------------------------------+
// TODO:
// - Add method to update TP, SL and close order


#include <stderror.mqh> 
#include <stdlib.mqh> 

#property copyright "Copyright 2015, jimbulux"
#property link      "https;//www.mql5.com"
#property version   "1.00"
#property strict

// INPUT SETTINGS
input int COMM_CHANNEL = 0;
//input int EXPERT_MAGIC_NUM = 1576585;

// COMM RESPONSE MESSAGES
#define COMM_TX_CONNECTED "TERM;RX;CONNECTED"
#define COMM_TX_DISCONNECTED "TERM;RX;DISCONNECTED"
#define COMM_TX_QUOTE "TERM;RX;QUOTE;"
#define COMM_TX_PING "TERM;RX;COMM;PING"
#define COMM_TX_PRICEBAR_RESP  "TERM;RX;PRICEBAR;RESP"
#define COMM_TX_PRICEBAR_MISSINGDATA  "TERM;RX;PRICEBAR;MISSINGDATA"
#define COMM_NEW_ORDER_RESP  "TERM;RX;NEWORDER;RESP"
#define COMM_CANCEL_ORDER_RESP  "TERM;RX;CANCELORDER;RESP"
#define COMM_MODIFY_ORDER_RESP  "TERM;RX;MODIFYORDER;RESP"
#define COMM_SYMBOLS_LIST_RESP  "TERM;RX;SYMBOLS;LIST;RESP"

// COMM REQUEST MESSAGES
#define COMM_RX_HEADER "TERM;TX;"
#define COMM_RX_CONNECT "TERM;TX;COMM;CONNECT" 
#define COMM_RX_DISCONNECT "TERM;TX;COMM;DISCONNECT"
#define COMM_RX_PING "TERM;TX;COMM;PING"
#define COMM_RX_QUOTES_START "TERM;TX;QUOTES;START"
#define COMM_RX_QUOTES_STOP "TERM;TX;QUOTES;STOP"
#define COMM_RX_PRICEBAR_REQ  "TERM;TX;PRICEBAR;REQ"
#define COMM_NEW_ORDER_REQ  "TERM;TX;NEWORDER;REQ"
#define COMM_CANCEL_ORDER_REQ  "TERM;TX;CANCELORDER;REQ"
#define COMM_MODIFY_ORDER_REQ  "TERM;TX;MODIFYORDER;REQ"
#define COMM_SYMBOLS_LIST_REQ  "TERM;TX;SYMBOLS;LIST;REQ"

#define TRADE_SHORT_STOP_EXIT   6
#define TRADE_LONG_STOP_EXIT 7
#define TRADE_MARKET_EXIT   8
#define TRADE_LONG_LIMIT_EXIT   9
#define TRADE_SHORT_LIMIT_EXIT 10
#define TRADE_SHORT_STOP_LIMIT_EXIT 11
#define TRADE_LONG_STOP_LIMIT_EXIT 12
#define TRADE_SHORT_STOP_LIMIT_ENTRY 13
#define TRADE_LONG_STOP_LIMIT_ENTRY 14

// Timed events and functions
#define PING_WATCHDOG_LIMIT 15         // In seconds
#define PROCESSES_TASK_INTERVAL  2000  // In miliseconds
#define TIMER_PERIOD 200               // Default loop tick period
// Special characters
#define NEWLINE_CHAR   "\r\n"
#define MSG_SEPARATOR   ";"
#define SYMBOLS_LIMIT   1024
// Constants
#define COMM_FILE_NAME "MtSharedFile"
//#define COMMENT_PREFIX "FEDRV"

//+------------------------------------------------------------------+
//| Classes and structs                                              |
//+------------------------------------------------------------------+
class Quote {
   public: 
      string QuoteSymbol;
      double QuoteAskPrice;
      double QuoteBidPrice;
      long QuoteVolume; 
};
//+------------------------------------------------------------------+
class MtOrder {
   public: 
      string Symbol;
      string OriginalSymbol;
      double AskPrice;
      double BidPrice;
      double TakeProfit;
      double StopLoss;
      double Volume;
      string Comment;
      int OrderType;
      int OrderId;
      string OriginalOrderId; // Loopback to NS. Ugly but no other way of doing it
      int TicketId;
      void MtOrder(void);
      void MtOrder(string commMessage) {
         string data[];
         StringSplit(commMessage, StringGetCharacter(MSG_SEPARATOR, 0), data);
         OrderId = (int)StringToInteger(data[0]);
         TicketId = GetTicketIdFromOrderId((int)StringToInteger(data[0]));
         OrderType = (int)StringToInteger(data[1]); // Map between order types matches the .NET driver type
         datetime expirationTime = StringToTime(data[2]);
         OriginalSymbol = data[3];
         StringReplace(data[3], "/", "");
         Symbol = data[3];
         StringReplace(data[4], ",", ".");
         StringReplace(data[5], ",", ".");
         StringReplace(data[6], ",", ".");
         StringReplace(data[7], ",", ".");
         StringReplace(data[8], ",", ".");
         int symbolDigits = (int)MarketInfo(Symbol, MODE_DIGITS);
         BidPrice = NormalizeDouble(StringToDouble(data[4]), symbolDigits);
         AskPrice = NormalizeDouble(StringToDouble(data[5]), symbolDigits);
         Volume = StringToDouble(data[6]);
         TakeProfit = NormalizeDouble(StringToDouble(data[7]), symbolDigits);
         StopLoss = NormalizeDouble(StringToDouble(data[8]), symbolDigits);
         Comment = data[9];
         OriginalOrderId = data[10];
         if(AskPrice == 0) {
            AskPrice = MarketInfo(Symbol, MODE_ASK);
         }
         if(BidPrice == 0) {
            BidPrice = MarketInfo(Symbol, MODE_BID);
         }
      }
};
//+------------------------------------------------------------------+
class PriceBar {
   private:
   public: 
      int Interval;
      double OpenPrice;
      double ClosePrice;
      double HighPrice;
      double LowPrice;
      long TickVolume;
      long RealVolume;
      string PriceSymbol;
      datetime TimeStamp;
      void PriceBar(void);      
      string ToPayloadMessage(void);  
};
PriceBar::PriceBar(void) {}
string PriceBar::ToPayloadMessage(void) {
   return DoubleToStr(OpenPrice) + MSG_SEPARATOR + DoubleToStr(ClosePrice) + MSG_SEPARATOR + 
      DoubleToStr(HighPrice) + MSG_SEPARATOR + DoubleToStr(LowPrice) + MSG_SEPARATOR + 
      PriceSymbol + MSG_SEPARATOR + IntegerToString(Interval) + MSG_SEPARATOR + 
      IntegerToString(TickVolume) + MSG_SEPARATOR + TimeToStr(TimeStamp, TIME_DATE|TIME_SECONDS);
}

//+------------------------------------------------------------------+
//| Local variables                                                  |
//+------------------------------------------------------------------+
string sharedFileInName = "";       // Comm channel for input stream 
string sharedFileOutName = "";      // Comm channel for output stream
bool isConnected = false;
bool quotesEnabled = false;
string quotesSymbols = "";
double pingWatchDog = 0;
int processesCheckMsCounter = 0;
int lastQuoteSymbolIndex = 0;
Quote *activeQuotes[SYMBOLS_LIMIT]; // To double check the previuous value not to send the same value again
string symbolsToQuote[];            // Symbols to quote - continuosly send ticks
string pendingOrders[];             // List of pending orders
string limitClosedOrders[];         // List of orders by limits {TP, SL}
static int lastPendingOrdersCount;  // Number of last pending orders
string commMessages[];
int orderIdLookup[][2];             // Order id lookup table

// Map for order types
int orderTypesMap[][2] = 
   {
    {TRADE_SHORT_STOP_LIMIT_ENTRY, OP_SELLLIMIT}, 
    {TRADE_LONG_STOP_LIMIT_ENTRY, OP_BUYLIMIT}
   };               

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{    
   Test();
   sharedFileInName = COMM_FILE_NAME + ".0." + IntegerToString(COMM_CHANNEL);       //0 In direcion
   sharedFileOutName = COMM_FILE_NAME + ".1." + IntegerToString(COMM_CHANNEL);      //1 Out direction 
   ClearFileContent(sharedFileOutName);
   ClearFileContent(sharedFileInName);
   FillListOfSymbols();
   LoadPendingOrders();
   CheckOrdersClosedByLimits(true); // Check already closed orders by TP, SL
   
   if(Connect(sharedFileInName)) {
      isConnected = true;
      EventSetMillisecondTimer(TIMER_PERIOD);
   }
   return(INIT_SUCCEEDED);
}
int FindOrderType(int orderType) {
   int res = -1;
   for(int i = 0; i < ArraySize(orderTypesMap); i++) {
      if(orderTypesMap[i][0] == orderType) {
         res = orderTypesMap[i][1];
         break;
      }
   }
   return res;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();   
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   //Test();
   if(isConnected) {
      // 1] Read file content
      if(WaitForRead(commMessages)) {
         for(int i = 0; i < ArraySize(commMessages); i++) {
            ParseMessage(commMessages[i]);
         }
         ClearList(commMessages);
      }
      // 2] Check for extra processes to run.
      if(processesCheckMsCounter >= PROCESSES_TASK_INTERVAL) {
         CheckProcesses();
         processesCheckMsCounter = 0;
      }
      processesCheckMsCounter += TIMER_PERIOD;
   }
}
//+------------------------------------------------------------------+

void CheckProcesses()
{
   if(isConnected) {
      pingWatchDog += TIMER_PERIOD/1000.0; // Approx 200ms
      
      // 1] Detect pending orders that got filled
      if (PendingOrdersCountChanged()) {
            for(int i = 0; i < OrdersTotal(); i++)                                                
            {
               if (OrderSelect(i, SELECT_BY_POS) == true)
               {
                  int magic = OrderMagicNumber();
                  string comment = OrderComment();
                  int orderType = OrderType();
                  if (OrderType() < 2 && OrderMagicNumber() > 0)
                  {
                     string mn = IntegerToString(OrderTicket());
                     if(ListContains(pendingOrders, mn)) {
                        // Filled pending order found
                        string params[6];
                        params[0] = "1";
                        params[1] = IntegerToString(OrderMagicNumber());   // Magic number contains sender�s orderId;
                        params[2] = OrderSymbol();
                        params[3] = DoubleToString(OrderOpenPrice());
                        params[4] = DoubleToString(OrderLots());
                        params[5] = "";
                        SendCommMessage(COMM_NEW_ORDER_RESP, params);
                        RemoveFromList(pendingOrders, mn);
                        ClearList(params);
                     }
                  }
               }
            }
      }
      // 2] Check for orders closed by TP/SL
      CheckOrdersClosedByLimits(); // Checking the SL/TP
      
      // 3] Send updated quotes
      if(quotesEnabled) {
         string quoteBuffer = "";
         int foundSymbolIndex = -1;
         // Send all the symbols
         int numOfSymbols = SymbolsTotal(true);
         for(int i = 0; i < ArraySize(symbolsToQuote); i++)
         {
            for(int j = 0; j < numOfSymbols; j++) {
                if(StringFind(SymbolName(j, true), symbolsToQuote[i]) != -1) {                  
                  foundSymbolIndex = j;
                  break;  
                }    
            } 
            if(foundSymbolIndex == -1) {
               break;
            }
            int symbolQuoteIndex = GetQuoteIndexBySymbolName(SymbolName(foundSymbolIndex, true));
            if(activeQuotes[symbolQuoteIndex].QuoteAskPrice != MarketInfo(activeQuotes[symbolQuoteIndex].QuoteSymbol,MODE_ASK) || 
               activeQuotes[symbolQuoteIndex].QuoteBidPrice != MarketInfo(activeQuotes[symbolQuoteIndex].QuoteSymbol,MODE_BID))
            {
               activeQuotes[symbolQuoteIndex].QuoteAskPrice = MarketInfo(activeQuotes[symbolQuoteIndex].QuoteSymbol,MODE_ASK);
               activeQuotes[symbolQuoteIndex].QuoteBidPrice = MarketInfo(activeQuotes[symbolQuoteIndex].QuoteSymbol,MODE_BID);
               activeQuotes[symbolQuoteIndex].QuoteVolume = iVolume(SymbolName(foundSymbolIndex, true), 1, 0);
               string timeStamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
               quoteBuffer += COMM_TX_QUOTE + activeQuotes[symbolQuoteIndex].QuoteSymbol + MSG_SEPARATOR + DoubleToStr(activeQuotes[symbolQuoteIndex].QuoteAskPrice) + MSG_SEPARATOR 
                  + DoubleToStr(activeQuotes[symbolQuoteIndex].QuoteBidPrice) + MSG_SEPARATOR + timeStamp + MSG_SEPARATOR + IntegerToString(activeQuotes[symbolQuoteIndex].QuoteVolume) + NEWLINE_CHAR;
            }
         }
         if(quoteBuffer != "") {
            SendMessage(StringSubstr(quoteBuffer, 0, StringLen(quoteBuffer) - StringLen(NEWLINE_CHAR)));  // Remove last newline character
         }
      }
   }
}

bool Connect(string filePath)
{  
   bool isConn = false;
   ClearFileContent(filePath);
   int fh = FileOpen(filePath, FILE_COMMON|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_TXT);
   if(fh!=INVALID_HANDLE && FileSeek(fh, 0, SEEK_END)){
      isConn = true;
   }
   FileClose(fh);
   return isConn;
}

bool ClearFileContent(string filePath)
{
   bool contentCleared = false;
   int fh = FileOpen(filePath, FILE_COMMON|FILE_WRITE|FILE_SHARE_WRITE|FILE_SHARE_READ);
   if(fh != INVALID_HANDLE) {
      contentCleared = true;
   }
   else {
      Print("Unable to clear file content. Error code; " + IntegerToString(GetLastError()));
   }
   FileClose(fh);
   return contentCleared;
}

void SendMessage(string message)
{
   int fh = FileOpen(sharedFileOutName, FILE_COMMON|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_TXT);
   if(fh!=INVALID_HANDLE && FileSeek(fh, 0, SEEK_END))
   {
      FileWriteString(fh, message + "\r\n", StringLen(message));
   }
   else 
   {
      Print("Unable to send message; " + IntegerToString(GetLastError()));
   }
   FileClose(fh);
} 

// TODO; Rewrite into file monitoring using FindFirstChangeNotification function
bool WaitForRead(string &messages[])
{
   bool succes = false;
   int fh = FileOpen(sharedFileInName, FILE_COMMON|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_TXT);
   if(fh!=INVALID_HANDLE && !IsStopped())
   {
      FileSeek(fh, 0,  SEEK_SET);
      while(!FileIsEnding(fh))
      {
         string line = FileReadString(fh);
         if(StringFind(line, COMM_RX_HEADER) != -1 && line != "") {
            AddToList(messages, line);
            succes = true;
         }   
      }
   }
   FileClose(fh);
   if(succes) {
      ClearFileContent(sharedFileInName);
   }
   return succes;
}

void Disconnet()
{
   isConnected = false;
}

int FindOrderByMagicId(int magicId) 
{
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS) && OrderMagicNumber() == magicId) {
         return OrderTicket();
      }
   }
   return -1;
}

int GetHistoryQuote(string symbol, datetime startTimeStamp, int interval, PriceBar &pb[], datetime endTimeStamp)
{
   MqlRates rates[];
   string foundSymbol = symbol;
   for(int i = 0; i < SymbolsTotal(true); i++) {
      string marketSymbolName = SymbolName(i, true);
      if(StringFind(marketSymbolName, symbol)!= -1) {
         foundSymbol = marketSymbolName;
         break;
      }
   }
   int numOfCopiedRates = CopyRates(foundSymbol, interval, startTimeStamp, endTimeStamp, rates);
   if(numOfCopiedRates <= 0 ) {
      return 0;
   }
   ArrayResize(pb, numOfCopiedRates);
   for(int i = 0; i < numOfCopiedRates; i++) {
      pb[i].PriceSymbol = symbol;
      pb[i].TimeStamp = rates[i].time;
      pb[i].ClosePrice = rates[i].close;
      pb[i].OpenPrice = rates[i].open;
      pb[i].LowPrice = rates[i].low;
      pb[i].HighPrice = rates[i].high;
      pb[i].TickVolume = rates[i].tick_volume;
      pb[i].RealVolume = rates[i].real_volume;
      pb[i].Interval = interval;
   }
   
   return numOfCopiedRates;
}

void UpdateQuoteSymbol(int symbolIndex, string symbolName)
{
   if(activeQuotes[symbolIndex] == NULL) {
      activeQuotes[symbolIndex] = new Quote();
   }
   activeQuotes[symbolIndex].QuoteSymbol = symbolName;
   activeQuotes[symbolIndex].QuoteAskPrice = MarketInfo(symbolName,MODE_ASK);
   activeQuotes[symbolIndex].QuoteBidPrice = MarketInfo(symbolName,MODE_BID);
}

int GetQuoteIndexBySymbolName(string symbolName)
{
   int numOfSymbols = SymbolsTotal(true);
   for(int i = 0; i < numOfSymbols; i++)
   {
      if(StringCompare(activeQuotes[i].QuoteSymbol, symbolName, false) == 0)
      {
         return i;
      }
   }
   return NULL;
}

void FillListOfSymbols()
{
   int numOfSymbols = SymbolsTotal(true);
   for(int i = 0; i < numOfSymbols; i++)
   {
      UpdateQuoteSymbol(i, SymbolName(i, true));
   }
}

void LoadPendingOrders() {
   for(int i = 0; i < OrdersTotal(); i++)                                                
   {
      if (OrderSelect(i, SELECT_BY_POS) == true)
      {
         if (OrderType() > 1 && OrderMagicNumber() > 0)
         {
            AddToList(pendingOrders, IntegerToString(OrderMagicNumber()));
         }
      }
   }
}

//------------------------------------------------------
//-------------- HELPER METHODS ------------------------
//------------------------------------------------------

bool FileRemoveContent(string fileName, string contentToRemove)
{
   bool contentRemoved = false;
   int fh = FileOpen(fileName, FILE_COMMON|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_TXT);
   if(fh != INVALID_HANDLE) {
      string fileContent = "";
      FileSeek(fh, 0, SEEK_SET);
      while(!FileIsEnding(fh))
      {
         string line = FileReadString(fh);
         if((StringFind(line, contentToRemove) == -1) && (line != "")) {
            fileContent += line;
         }
      }
      FileClose(fh);
      if(ClearFileContent(fileName)) {
         fh = FileOpen(fileName, FILE_COMMON|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_TXT);
         if(fh!=INVALID_HANDLE && FileSeek(fh, 0, SEEK_END)){
            if (FileWriteString(fh, fileContent, StringLen(fileContent)) != 0) {
               contentRemoved = true;   
            } else {
               Print("Error while writing content to file. Err. code; " + IntegerToString(GetLastError()));
            }
         }
         FileClose(fh);
      }
      else {
         Print("Could not remove content!!!. Err. code; " + IntegerToString(GetLastError()));
      }
   }
   return contentRemoved;
}

void AddSymbolToQuote(string symbol) {
   int stqSize = ArraySize(symbolsToQuote);
   for(int i = 0; i < stqSize; i++) {
      if(symbolsToQuote[i] == symbol) {
         return;
      }
   } 
   ArrayResize(symbolsToQuote, stqSize+1);
   symbolsToQuote[stqSize] = symbol;
}

void RemoveQuotedSymbol(string symbol) {
   int stqSize = ArraySize(symbolsToQuote);
   string newQuotedSymbolsArray[];
   for(int i = 0; i < stqSize; i++) {
      if(symbolsToQuote[i] == symbol) {
         continue;
      }
      else {
         ArrayResize(newQuotedSymbolsArray, ArraySize(newQuotedSymbolsArray) + 1);
         newQuotedSymbolsArray[ArraySize(newQuotedSymbolsArray)-1] = symbolsToQuote[i];
      }
   }
   ArrayFree(symbolsToQuote);
   ArrayResize(symbolsToQuote, ArraySize(newQuotedSymbolsArray));
   ArrayCopy(symbolsToQuote, newQuotedSymbolsArray);
}

void ClearQuotedSymbols() {
   ArrayFree(symbolsToQuote);
}


void AddToList(string &listArray[], string value) {
   int stqSize = ArraySize(listArray);
   for(int i = 0; i < stqSize; i++) {  // Check for existing values
      if(listArray[i] == value) {
         return;
      }
   }
   // Add new value
   ArrayResize(listArray, stqSize+1);
   listArray[stqSize] = value;
}

void RemoveFromList(string &listArray[], string value) {
   int stqSize = ArraySize(listArray);
   string newListArray[];
   for(int i = 0; i < stqSize; i++) {
      if(listArray[i] == value) {
         continue;
      }
      else {
         ArrayResize(newListArray, ArraySize(newListArray) + 1);
         newListArray[ArraySize(newListArray)-1] = listArray[i];
      }
   }
   ArrayFree(listArray);
   ArrayResize(listArray, ArraySize(newListArray));
   ArrayCopy(listArray, newListArray);
}

void ClearList(string &listArray[]) {
   ArrayFree(listArray);
}

bool ListContains(string &listArray[], string value) {
   for(int i = 0; i < ArraySize(listArray); i++) {  // Check for existing values
      if(listArray[i] == value) {
         return true;
      }
   }
   return false;
}

bool PendingOrdersCountChanged() {
   int count = 0;
   bool countChanged = false;

   for(int i = 0; i < OrdersTotal(); i++)                                                
   {
      if (OrderSelect(i, SELECT_BY_POS) == true)
      {
         if (OrderType() > 1 && OrderMagicNumber() > 0)
         {
            count++;
         }
      }
   }
   if (count != lastPendingOrdersCount)
   {
      countChanged = true;
      lastPendingOrdersCount = count;
   }

   return countChanged;
}

void SendCommMessage(string command, string &params[])
{
   string messageToSend = command + MSG_SEPARATOR;
   for(int i = 0; i < ArraySize(params); i++) {
      messageToSend += params[i] + ((i == ArraySize(params)-1) ? "" : MSG_SEPARATOR);
   }
   SendMessage(messageToSend);
}

void OpenNewOrder(MtOrder &o) {
   Print("Opening new trade: " + IntegerToString(o.OrderType) + ":" + DoubleToString(o.AskPrice) + ":" + DoubleToString(o.TakeProfit) + ":" + DoubleToString(o.StopLoss));
   int ticketId = OrderSend(o.Symbol, o.OrderType, o.Volume, o.AskPrice, 0, o.StopLoss, o.TakeProfit, o.Comment, o.OrderId, 0, clrGreen);
   if(ticketId < 0) {
      Print("Error opening new trade. Error desc: " + ErrorDescription(GetLastError()));
      SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalOrderId + MSG_SEPARATOR + ErrorDescription(GetLastError()));
   } else {
      if(OrderSelect(ticketId, SELECT_BY_TICKET)) {
         if(o.OrderType == OP_BUYLIMIT || o.OrderType == OP_BUYSTOP || o.OrderType == OP_SELLSTOP || o.OrderType == OP_SELLLIMIT) {
            AddToList(pendingOrders, IntegerToString(ticketId));
            SendMessage(COMM_MODIFY_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + "0" + MSG_SEPARATOR + "0" + MSG_SEPARATOR + o.OriginalOrderId);
         } else {
            SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalSymbol + MSG_SEPARATOR + DoubleToString(o.AskPrice) + MSG_SEPARATOR + DoubleToString(o.Volume) + MSG_SEPARATOR + o.OriginalOrderId);
         }
      }
      else {
         Print("Couldn't find existing order. Error desc: " + ErrorDescription(GetLastError()));
         SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalSymbol + MSG_SEPARATOR + ErrorDescription(GetLastError()));
      }
   }      
}

void ModifyExistingOrder(MtOrder &o) {
   Print("Modifying existing trade: " + IntegerToString(o.OrderType) + ":" + DoubleToString(o.AskPrice) + ":" + DoubleToString(o.TakeProfit) + ":" + DoubleToString(o.StopLoss));
   if(OrderModify(o.TicketId, o.AskPrice, o.StopLoss, o.TakeProfit, 0)) {
      SendMessage(COMM_MODIFY_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + "0" + MSG_SEPARATOR + "0" + MSG_SEPARATOR + o.OriginalOrderId);
   } else {
      Print("Couldn't modify existing order. Error desc: " + ErrorDescription(GetLastError()));
      SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalOrderId + MSG_SEPARATOR + ErrorDescription(GetLastError()));
   }
}

bool OrderExists(MtOrder &o) {
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS) && (o.TicketId == OrderTicket() || o.OrderId == OrderMagicNumber())) {
         return true;
      }
   }
   return false;
}

void CheckOrdersClosedByLimits(bool initLoad = false) {
   for (int i = 0; i < OrdersHistoryTotal(); i++)
   {
      if (OrderSelect(i,SELECT_BY_POS,MODE_HISTORY) && (MathAbs(TimeCurrent() - OrderCloseTime())/3600.0) < 24)
      {
         double allowedSlippage = MarketInfo(OrderSymbol(), MODE_POINT) * 50; // Max slippage for TP. SL. Detection is 5pips
         if ((MathAbs(OrderStopLoss()-OrderClosePrice() < allowedSlippage) || MathAbs(OrderTakeProfit()-OrderClosePrice()) < allowedSlippage) && !ListContains(limitClosedOrders, IntegerToString(OrderTicket())) && OrderMagicNumber() > 0) {
            if(!initLoad)
               SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "2" + MSG_SEPARATOR + IntegerToString(OrderMagicNumber()) + MSG_SEPARATOR + OrderSymbol() + MSG_SEPARATOR + DoubleToString(OrderClosePrice()) + MSG_SEPARATOR + DoubleToString(OrderLots()) + MSG_SEPARATOR + "");
            AddToList(limitClosedOrders, IntegerToString(OrderTicket()));
         }
      }
   }
}

int GetTicketIdFromOrderId(int orderId){
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS)) {
         int mag = OrderMagicNumber();
         if(OrderMagicNumber() == orderId) {
            return OrderTicket();
         }
      }
   }
   return -1;

}

//------------------------------------------------------------------------------------------------------------
//--------------------------------------- MAIN COMM MESSAGE LOOP ---------------------------------------------
//------------------------------------------------------------------------------------------------------------

void ParseMessage(string message)
{
   if(message == COMM_RX_CONNECT) {
      SendMessage(COMM_TX_CONNECTED);
      ClearQuotedSymbols();
   } 
   else if(message == COMM_RX_DISCONNECT) {
      SendMessage(COMM_TX_DISCONNECTED);
   }
   else if(StringFind(message, COMM_RX_QUOTES_START) != -1) {
      string payload = StringSubstr(message, StringLen(COMM_RX_QUOTES_START) + 1);  // +1 for separator char after command header
      string data[];
      StringSplit(payload, StringGetCharacter(MSG_SEPARATOR, 0), data);
      if(ArraySize(data) > 0) {
         AddSymbolToQuote(data[0]);
         quotesEnabled = true;   // Start sending sending symbol quotes
      }
   }
   else if(StringFind(message, COMM_RX_QUOTES_STOP) != -1) {
      string payload = StringSubstr(message, StringLen(COMM_RX_QUOTES_STOP) + 1);  // +1 for separator char after command header
      string data[];
      StringSplit(payload, StringGetCharacter(MSG_SEPARATOR, 0), data);
      if(ArraySize(data) > 0) {
         RemoveQuotedSymbol(data[0]);
         if(ArraySize(symbolsToQuote) == 0) {
            quotesEnabled = false;  // Stop sending symbol quotes
         }
      }
   }
   else if(message == COMM_RX_PING) {
      pingWatchDog = 0;
      SendMessage(COMM_TX_PING);
   }
   else if(StringFind(message, COMM_RX_PRICEBAR_REQ) != -1) {
      string payload = StringSubstr(message, StringLen(COMM_RX_PRICEBAR_REQ) + 1);  // +1 for separator char after command header
      string data[];
      StringSplit(payload, StringGetCharacter(MSG_SEPARATOR, 0), data);
      string symbol = data[0];
      datetime startBarTime = StrToTime(data[1]);
      int interval = StrToInteger(data[2]);
      bool allHistory = false;
      if(ArraySize(data) > 3) {  // Optional paramater
         allHistory = StringFind(data[3], "true")!=-1;
      }
      PriceBar pb[];
      int copiedBarsCount = GetHistoryQuote(symbol, startBarTime, interval, pb, TimeCurrent());
      if(copiedBarsCount > 0) {
         for(int i = 0; i < copiedBarsCount; i++) {
            SendMessage(COMM_TX_PRICEBAR_RESP + MSG_SEPARATOR + pb[i].ToPayloadMessage());
         }
      } 
      else {
         // Data not available in a history
         SendMessage(COMM_TX_PRICEBAR_MISSINGDATA);
      }
   }
   else if(StringFind(message, COMM_NEW_ORDER_REQ) != -1) {
      string payload = StringSubstr(message, StringLen(COMM_NEW_ORDER_REQ) + 1);  // +1 for separator char after command header
      MtOrder *o = new MtOrder(payload);
      
      if(o.OrderType < 6) {
            OpenNewOrder(o);
       } else if (o.OrderType == TRADE_SHORT_STOP_EXIT || o.OrderType == TRADE_LONG_STOP_EXIT || o.OrderType == TRADE_LONG_LIMIT_EXIT || o.OrderType == TRADE_SHORT_LIMIT_EXIT || o.OrderType == TRADE_SHORT_STOP_LIMIT_EXIT || o.OrderType == TRADE_LONG_STOP_LIMIT_EXIT) {
            if(OrderSelect(o.TicketId, SELECT_BY_TICKET) && OrderModify(o.TicketId, OrderOpenPrice(), o.StopLoss, o.TakeProfit, 0)) {
               SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalSymbol + MSG_SEPARATOR + DoubleToString(o.AskPrice) + MSG_SEPARATOR + DoubleToString(o.Volume) + MSG_SEPARATOR + o.OriginalOrderId);
            } else {
               SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalOrderId + MSG_SEPARATOR + ErrorDescription(GetLastError()));
            }
       } else if (o.OrderType == TRADE_MARKET_EXIT) {
            if(OrderSelect(o.TicketId, SELECT_BY_TICKET) && OrderClose(o.TicketId, OrderLots(), o.AskPrice, 5)) {
               SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalSymbol + MSG_SEPARATOR + DoubleToString(OrderClosePrice()) + MSG_SEPARATOR + DoubleToString(OrderLots()) + MSG_SEPARATOR + o.OriginalOrderId);
            } else {
               SendMessage(COMM_NEW_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + o.OriginalOrderId + MSG_SEPARATOR + ErrorDescription(GetLastError()));
            }
      } else if (o.OrderType == TRADE_SHORT_STOP_LIMIT_ENTRY || o.OrderType == TRADE_LONG_STOP_LIMIT_ENTRY) {
         o.OrderType = FindOrderType(o.OrderType); // Translate order type before commiting
         o.StopLoss = 0;   // NS Issue? Fix it on NS side
         if(OrderExists(o)) {
            ModifyExistingOrder(o);
         } else {
            OpenNewOrder(o);
         }
      }
   }
   else if(StringFind(message, COMM_CANCEL_ORDER_REQ) != -1) {
      string payload = StringSubstr(message, StringLen(COMM_CANCEL_ORDER_REQ) + 1);  // +1 for separator char after command header
      string data[];
      StringSplit(payload, StringGetCharacter(MSG_SEPARATOR, 0), data);
      int orderId = (int)StringToInteger(data[0]);
      string originOrderId = data[1];
	   int ticketId = GetTicketIdFromOrderId(orderId);
      if(OrderSelect(ticketId, SELECT_BY_TICKET)) {
         if(OrderType() > 1) {
            if(OrderDelete(ticketId)) {
               SendMessage(COMM_CANCEL_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(orderId) + MSG_SEPARATOR + originOrderId);
            }
            else {
               Print("Error deleting trade. Error desc: " + ErrorDescription(GetLastError()));
               SendMessage(COMM_CANCEL_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(orderId) + MSG_SEPARATOR + originOrderId + MSG_SEPARATOR + ErrorDescription(GetLastError()));
            }
         }
         else {
            if(OrderClose(ticketId, OrderLots(), Ask, 3, clrRed)) {
               SendMessage(COMM_CANCEL_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(orderId) + MSG_SEPARATOR + originOrderId);
            } else {
               Print("Error closing trade. Error desc: " + ErrorDescription(GetLastError()));
               SendMessage(COMM_CANCEL_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(orderId) + MSG_SEPARATOR + originOrderId + MSG_SEPARATOR + ErrorDescription(GetLastError()));
            }
         }
      }
      else {
         SendMessage(COMM_CANCEL_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(orderId) + MSG_SEPARATOR + originOrderId + MSG_SEPARATOR + "Order doesn't exist");         
      }
   }
   else if(StringFind(message, COMM_MODIFY_ORDER_REQ) != -1) {
      string payload = StringSubstr(message, StringLen(COMM_MODIFY_ORDER_REQ) + 1);  // +1 for separator char after command header
      MtOrder *o = new MtOrder(payload);     
      
      if(OrderSelect(o.TicketId, SELECT_BY_TICKET) && OrderModify(o.TicketId, OrderOpenPrice(), o.StopLoss, o.TakeProfit, 0)) {
         SendMessage(COMM_MODIFY_ORDER_RESP + MSG_SEPARATOR + "1" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + DoubleToString(o.StopLoss) + MSG_SEPARATOR + DoubleToString(o.TakeProfit));
      } else {
         SendMessage(COMM_MODIFY_ORDER_RESP + MSG_SEPARATOR + "0" + MSG_SEPARATOR + IntegerToString(o.OrderId) + MSG_SEPARATOR + ErrorDescription(GetLastError()));
      }
   }
   else if (StringFind(message, COMM_SYMBOLS_LIST_REQ) != -1) {
      string marketSymbolNames = "";
      for(int i = 0; i < SymbolsTotal(true); i++) {
         marketSymbolNames += SymbolName(i, true) + MSG_SEPARATOR;
      }
      SendMessage(COMM_SYMBOLS_LIST_RESP + MSG_SEPARATOR + marketSymbolNames);
   }
}

//------------------------------------------------------
//------------- TESTING METHODS ------------------------
//------------------------------------------------------

void Test() {
}