using System.ComponentModel;

namespace Cb.Mt4.Driver.Enums
{
    internal enum MtTermComMessages
    {
        [Description("TERM;")] MessageHeader,
        [Description("TERM;CONNECTED")] CommConnected,
        [Description("TERM;DISCONNECTED")] CommDisconected,
        [Description("TERM;ORDERS;TOTAL")] OrdersTotal,
    }

    internal enum MtTermReqMessages
    {
        [Description("TERM;TX;")] MessageHeader,
        [Description("TERM;TX;COMM;CONNECT")] Connect,
        [Description("TERM;TX;COMM;DISCONNECT")] Disconnect,
        [Description("TERM;TX;COMM;PING")] Ping,
        [Description("TERM;TX;ORDERS;TOTAL")] OrdersTotal,
        [Description("TERM;TX;QUOTES;START")] QuotesStart,
        [Description("TERM;TX;QUOTES;STOP")] QuotesStop,
        [Description("TERM;TX;PRICEBAR;REQ")] PriceBarRequest,
        [Description("TERM;TX;CANCELORDER;REQ")] CancelOrder,
        [Description("TERM;TX;SYMBOLS;LIST;REQ")] SymbolsList,
        [Description("TERM;TX;NEWORDER;REQ")] NewOrder,
        [Description("TERM;TX;MODIFYORDER;REQ")] ModifyOrder,
    }

    internal enum MtTermRespMessage
    {
        [Description("TERM;RX;")] MessageHeader,
        [Description("TERM;RX;CONNECTED")] CommConnected,
        [Description("TERM;RX;DISCONNECTED")] CommDisconected,
        [Description("TERM;RX;ORDERS;TOTAL")] OrdersTotal,
        [Description("TERM;RX;COMM;PING")] Ping,
        [Description("TERM;RX;QUOTE")] Quote,
        [Description("TERM;RX;PRICEBAR;RESP")] PriceBarResponse,
        [Description("TERM;RX;PRICEBAR;MISSINGDATA")] MissingHistoryData,
        [Description("TERM;RX;NEWORDER;RESP")] NewOrder,
        [Description("TERM;RX;CANCELORDER;RESP")] CancelOrder,
        [Description("TERM;RX;MODIFYORDER;RESP")] ModifyOrder,
        [Description("TERM;RX;SYMBOLS;LIST;RESP")] SymbolsList,
        [Description("TERM;RX;ORDERIDCHANGED;RESP")] OrderIdChanged,
    }
}