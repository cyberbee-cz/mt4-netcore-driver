using System;

namespace Cb.Mt4.Driver.Entities
{
    public class PriceQuote
    {
        public string Symbol { get; set; }
        public DateTime TimeStamp { get; set; }
        public double AskPrice { get; set; }
        public double BidPrice { get; set; }
        public double Volume { get; set; }
    }
}