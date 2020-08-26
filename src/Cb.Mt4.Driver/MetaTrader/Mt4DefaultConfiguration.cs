using Cb.Mt4.Driver.Interfaces;

namespace TradeAdvisor.Connectors.MetaTrader
{
    public class Mt4DefaultConfiguration : IMtConfiguration
    {
        public int CommChannelIndex => 0;
    }
}