using System;

namespace Cb.Mt4.Driver.Entities
{
    public class PriceBar
    {
        public DateTime TimeStamp { get; set; }
        public string Symbol { get; set; }
        public double High { get; set; }
        public double Low { get; set; }
        public double Open { get; set; }
        public double Close { get; set; }
        public int Interval { get; set; }
        public double Volume { get; set; }
        public DateTime OpenTime { get; set; }
    }
}