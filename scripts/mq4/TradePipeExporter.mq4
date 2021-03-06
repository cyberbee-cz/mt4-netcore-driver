//+------------------------------------------------------------------+
//|                                            TradePipeExporter.mq4 |
//|                                         Copyright 2014, jimbulux |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2014, jimbulux"
#property link      "http://www.mql5.com"
#property version   "1.00"
#property strict

#define COMM_CONNECTED "TERM:CONNECTED"
#define COMM_QUOTE "TERM:QUOTE:"
#define NEWLINE_CHAR "\n"

// TX Messages
#define COMM_RX_HEADER "TERM:TX:"
#define COMM_RX_CONNECT "TERM:TX:COMM:CONNECT" 
#define COMM_RX_DISCONNECT "TERM:TX:COMM:DISCONNECT"
#define COMM_RX_PING "TERM:TX:COMM:PING"
#define COMM_RX_QUOTES_START "TERM:TX:QUOTES:START"
#define COMM_RX_QUOTES_STOP "TERM:TX:QUOTES:STOP"

//+----------------------------Includes------------------------------+
#include <Files\FilePipe.mqh>


//+----------------------------Variables-----------------------------+
CFilePipe ExtPipe;
bool IsConnected = false;

//+----------------------------Functions-----------------------------+
int OnInit()
{
//--- create timer
   EventSetTimer(5);
   
   bool bfirst=true;
   // Opening named pipe server connection
   while(!IsStopped())
   {  
      if(ExtPipe.Open("\\\\.\\pipe\\My.Pipe.Server",FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE)!=INVALID_HANDLE)
         break;
      if(bfirst)
      {
         bfirst=false;
         Print("Client: waiting for pipe server");
      }
      Sleep(250);
   }
   if(IsStopped()) {
      IsConnected = false;
      return(INIT_FAILED);
   }
   IsConnected = true;

   //--- send connection established message
   SendMessage(COMM_CONNECTED + NEWLINE_CHAR);
   ExtPipe.Flush();

   //--- read data from server
   //Sleep(1000);
   string str = "";
   while(!IsStopped()) {
      if(!ExtPipe.ReadString(str))
      {
         Print("Client: reading string failed or nothing to read");
         //return(INIT_FAILED);
      }
      Alert("Server: \"",str,"\" received");
      //Sleep(1000);
   }
//---
   return(INIT_SUCCEEDED);
}

void OnTimer()
{
   if(IsConnected) {
      SendMessage(COMM_QUOTE + ":" + Symbol() + ":" + DoubleToStr(Bid) + ":" + DoubleToStr(Ask));
   }
}

// Message handling

void SendMessage(string message)
{
   if(IsConnected) 
   {
      if(!ExtPipe.WriteString(COMM_CONNECTED + NEWLINE_CHAR))
      {
         Print("Client: sending welcome message failed");
         return;
      }
   }
}


