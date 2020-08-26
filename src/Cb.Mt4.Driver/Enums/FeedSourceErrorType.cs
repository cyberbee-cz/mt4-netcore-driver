using System.ComponentModel;

namespace Cb.Mt4.Driver.Enums
{
    public enum FeedSourceErrorType
    {
        [Description("History for selected pricebar is missing")] HistoryNotAvailable,
        [Description("Error filling the requested order")] OrderFillError,
    }
}
