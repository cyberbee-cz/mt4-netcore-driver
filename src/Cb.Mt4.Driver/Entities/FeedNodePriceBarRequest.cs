using System;

namespace Cb.Mt4.Driver.Entities
{
    public class FeedNodePriceBarRequest
    {
        public string Symbol { get; set; }

        public int Interval { get; set; }

        public DateTime Since { get; set; }

        public bool IncludeHistoryData { get; set; }
    }
}
