using System;
using System.Collections.Generic;
using Cb.Mt4.Driver.Entities;
using Cb.Mt4.Driver.Enums;

namespace Cb.Mt4.Driver.Interfaces
{
    public interface IFeedConnector
    {
        ConnectionStatus ConnectionStatus { get; }
        ICollection<string> QuotableSymbols { get; }
        event EventHandler<PriceQuote> FeedQuoteChanged;
        event EventHandler<PriceBar> FeedPriceBarReceived;
        void RequestPriceBar(FeedNodePriceBarRequest pbRequest);
        void RequestQuotesStart(FeedNodeQuoteRequest quoteRequest);
        void RequestQuotesStop(FeedNodeQuoteRequest quoteRequest);
        void Connect();
        void Disconnect();
    }
}