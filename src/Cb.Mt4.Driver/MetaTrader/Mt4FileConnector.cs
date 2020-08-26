using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Cb.Mt4.Driver.Entities;
using Cb.Mt4.Driver.Enums;
using Cb.Mt4.Driver.Extensions;
using Cb.Mt4.Driver.Helpers;
using Cb.Mt4.Driver.Interfaces;

namespace Cb.Mt4.Driver
{
    public class Mt4FileConnector : IFeedConnector
    {
        #region Private properties
        private readonly string _mtFeedFilePath;
        private FileSystemWatcher _fsWatcher;
        private readonly IMtConfiguration _config;
        private bool _fsWatchTaskStarted = false;
        private const int FileAccessAttemptsLimit = 3;
        private Timer _connectionTimeoutTimer;
        private Timer _fileCheckingTimer;
        private readonly object _locker = new object();
        #endregion

        #region Public properites
        public const int DefaultFileCheckTimeout = 10000;   // 10s
        public const int DefaultConnectionTimeout = 5000;
        public const string CommFeedFileName = "MtSharedFile";
        public const string MetaQuotesCommonFilesPath = @"\MetaQuotes\Terminal\Common\Files\";
        public ConnectionStatus ConnectionStatus { get; private set; }
        public List<string> QuotedSymbols { get; private set; }
        public event EventHandler<PriceQuote> FeedQuoteChanged;
        public event EventHandler<PriceBar> FeedPriceBarReceived;
        public event EventHandler<FeedSourceErrorType> FeedSourceError;
        public ICollection<string> QuotableSymbols { get; private set; }
        #endregion

        public Mt4FileConnector(IMtConfiguration configuration)
        {
            _config = configuration;
            QuotedSymbols = new List<string>(0);
            _mtFeedFilePath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) + MetaQuotesCommonFilesPath;
            ConnectionStatus = ConnectionStatus.Disconnected;
        }    

        public void Connect()
        {
            if(ConnectionStatus == ConnectionStatus.Disconnected)
            {
                ClearChannel(MtCommChannelDirection.In);
                ClearChannel(MtCommChannelDirection.Out);
                ConnectionStatus = ConnectionStatus.Connecting;
                StartWatchTask();
                SendMtCommandAsync(MtTermReqMessages.Connect);
                StartConnectionTimeoutTimer();
                StartFileCheckingTimer();
            }
        }

        public void Disconnect()
        {
            if (ConnectionStatus == ConnectionStatus.Connected)
            {
                SendMtCommandAsync(MtTermReqMessages.Disconnect);
                StopWatchTask();
                StopConnectionTimeoutTimer();
                StopFileCheckingTimer();
            }
        }

        public void RequestPriceBar(FeedNodePriceBarRequest pbRequest)
        {
            SendMtCommandAsync(MtCommHelper.CreateCommandMessage(MtTermReqMessages.PriceBarRequest, pbRequest.Symbol,
                pbRequest.Since, pbRequest.Interval, pbRequest.IncludeHistoryData));
        }

        public void RequestQuotesStart(FeedNodeQuoteRequest quoteRequest)
        {
            if(QuotedSymbols.Contains(quoteRequest.Symbol)) return;
            SendMtCommandAsync(MtCommHelper.CreateCommandMessage(MtTermReqMessages.QuotesStart, quoteRequest.Symbol));
            QuotedSymbols.Add(quoteRequest.Symbol);
        }

        public void RequestQuotesStop(FeedNodeQuoteRequest quoteRequest)
        {
            SendMtCommandAsync(MtCommHelper.CreateCommandMessage(MtTermReqMessages.QuotesStop, quoteRequest.Symbol));
            if (QuotedSymbols.Contains(quoteRequest.Symbol))
            {
                QuotedSymbols.Remove(quoteRequest.Symbol);
            }
        }


        #region Private methods

        private void ClearChannel(MtCommChannelDirection channelDirection)
        {
            using (var fs = new FileStream(GetMtSharedFileStreamPath(channelDirection), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite))
            {
                fs.SetLength(0);
                fs.Close();
            }
        }

        private void ClearChannel(FileStream fs)
        {
            fs.SetLength(0);
            fs.Close();
        }

        private string GetMtSharedFileStreamPath(MtCommChannelDirection channelDirection) => _mtFeedFilePath + GetChannelFileName(channelDirection);
        
        /// <summary>
        /// Monitors file changes
        /// </summary>
        private void StartWatchTask()
        {
            _fsWatcher = new FileSystemWatcher
            {
                Path = _mtFeedFilePath,
                Filter = GetChannelFileName(MtCommChannelDirection.In),
                NotifyFilter = NotifyFilters.LastWrite,
                EnableRaisingEvents = true,
            };
            _fsWatcher.Changed += async (sender, eventArgs) => 
            {
                await Task.Factory.StartNew(() =>  { TryReadInputFile(eventArgs.FullPath); });
            };
            _fsWatchTaskStarted = true;
        }

        private void TryReadInputFile(string changeFilePath = null)
        {
            if (changeFilePath == null || string.Equals(changeFilePath, GetMtSharedFileStreamPath(MtCommChannelDirection.In), StringComparison.InvariantCultureIgnoreCase))
            {
                string rawContent = null;
                DisableFileMonitoring();
                using (var fs = new FileStream(GetMtSharedFileStreamPath(MtCommChannelDirection.In), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite))
                {
                    using (var sr = new StreamReader(fs))
                    {
                        rawContent = sr.ReadToEnd();
                        ClearChannel(fs);
                    }
                }
                var rxMessages = rawContent.Split(new[] { Environment.NewLine }, StringSplitOptions.None).Where(i => i.Contains(MtTermRespMessage.MessageHeader.GetDescription()));
                ParseMessages(rxMessages);
                EnableFileMonitoring();
            }
        }

        private void StopWatchTask()
        {
            _fsWatchTaskStarted = false;
            _fsWatcher.Dispose();
            _fsWatcher = null;
        }

        private void ParseMessages(IEnumerable<string> messages)
        {
            // var priceQuotes = messages.Where(msg => msg.Contains(MtTermRespMessage.Quote.GetDescription())).Select(pq => 
            // {
            //     var data = MtCommHelper.GetCommandData(MtTermRespMessage.Quote, pq);
            //     return new PriceQuote
            //     {
            //         Symbol = CheckSymbol(data[0]),
            //         AskPrice = Convert.ToDouble(data[1], CultureInfo.InvariantCulture),
            //         BidPrice = Convert.ToDouble(data[2], CultureInfo.InvariantCulture),
            //         TimeStamp = MetatraderHelper.ParseMtDateTime(data[3]),
            //         Volume = Convert.ToDouble(data[4], CultureInfo.InvariantCulture),
            //     };
            // }).ToList();
            // if(priceQuotes.Any())
            //     FeedQuoteChanged?.Invoke(this, priceQuotes);
            // var priceBars = new List<PriceBar>(0);
            messages.ToList().ForEach(msg =>
            {
                if (msg.Contains(MtTermRespMessage.CommConnected.GetDescription()))
                {
                    ConnectionStatus = ConnectionStatus.Connected;
                    StopConnectionTimeoutTimer();
                }
                else if (msg.Contains(MtTermRespMessage.CommDisconected.GetDescription()))
                {
                    ConnectionStatus = ConnectionStatus.Disconnected;
                }
                else if (msg.Contains(MtTermRespMessage.Quote.GetDescription()))
                {
                    var data = MtCommHelper.GetCommandData(MtTermRespMessage.Quote, msg);
                    FeedQuoteChanged?.Invoke(this, new PriceQuote
                    {
                        Symbol = CheckSymbol(data[0]),
                        AskPrice = Convert.ToDouble(data[1], CultureInfo.InvariantCulture),
                        BidPrice = Convert.ToDouble(data[2], CultureInfo.InvariantCulture),
                        TimeStamp = MetatraderHelper.ParseMtDateTime(data[3]),
                        Volume = Convert.ToDouble(data[4], CultureInfo.InvariantCulture),
                    });
                }
                else if (msg.Contains(MtTermRespMessage.PriceBarResponse.GetDescription()))
                {
                    var data = MtCommHelper.GetCommandData(MtTermRespMessage.PriceBarResponse, msg);
                    var pb = new PriceBar
                    {
                        Open = Convert.ToDouble(data[0], CultureInfo.InvariantCulture),
                        Close = Convert.ToDouble(data[1], CultureInfo.InvariantCulture),
                        High = Convert.ToDouble(data[2], CultureInfo.InvariantCulture),
                        Low = Convert.ToDouble(data[3], CultureInfo.InvariantCulture),
                        Symbol = CheckSymbol(data[4]),
                        Interval = Convert.ToInt32(data[5]),
                        Volume = Convert.ToDouble(data[6], CultureInfo.InvariantCulture),
                        OpenTime = MetatraderHelper.ParseMtDateTime(data[7])
                    };
                    FeedPriceBarReceived?.Invoke(this, pb);
                }
                else if (msg.Contains(MtTermRespMessage.MissingHistoryData.GetDescription()))
                {
                    FeedSourceError?.Invoke(this, FeedSourceErrorType.HistoryNotAvailable);
                }
                else if (msg.Contains(MtTermRespMessage.SymbolsList.GetDescription()))
                {
                    var data = MtCommHelper.GetCommandData(MtTermRespMessage.SymbolsList, msg);
                    QuotableSymbols = data.ToList();
                }
            });
        }

        private void StartConnectionTimeoutTimer()
        {
            _connectionTimeoutTimer = new Timer(TimerCallBack, null, DefaultConnectionTimeout, DefaultConnectionTimeout);
        }

        private void StopConnectionTimeoutTimer()
        {
            if(_connectionTimeoutTimer != null)
                _connectionTimeoutTimer.Dispose();
        }

        private void TimerCallBack(object state)
        {
            if(ConnectionStatus != ConnectionStatus.Connected || ConnectionStatus != ConnectionStatus.Error)
            {
                ConnectionStatus = ConnectionStatus.Error;
            }
        }

        private void StartFileCheckingTimer()
        {
            _fileCheckingTimer = new Timer((state) => TryReadInputFile(), null, DefaultFileCheckTimeout, DefaultFileCheckTimeout);
        }

        private void StopFileCheckingTimer()
        {
            if(_fileCheckingTimer != null)
                _fileCheckingTimer.Dispose();
        }

        private void FileCheckingCallbackTimerCallBack(object state)
        {
            if(ConnectionStatus != ConnectionStatus.Connected || ConnectionStatus != ConnectionStatus.Error)
            {
                ConnectionStatus = ConnectionStatus.Error;
            }
        }

        private string GetChannelFileName(MtCommChannelDirection direction)
        {
            switch(direction)
            {
                case MtCommChannelDirection.In:
                    return ($"{CommFeedFileName}.{MtCommChannelDirection.Out}.{_config.CommChannelIndex}").ToLowerInvariant();
                case MtCommChannelDirection.Out:
                default:
                    return ($"{CommFeedFileName}.{MtCommChannelDirection.In}.{_config.CommChannelIndex}").ToLowerInvariant();
            }   
        }

        private async void SendMtCommandAsync(MtTermReqMessages command) 
            => await Task.Factory.StartNew(() => {SendMtCommandAsync(command.GetDescription());});

        private async void SendMtCommandAsync(string message)
        {
            using (var fs = new FileStream(GetMtSharedFileStreamPath(MtCommChannelDirection.Out), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite))
            {
                string rawContent = null;
                using (var sr = new StreamReader(fs))
                {
                    rawContent = await sr.ReadToEndAsync();
                    if (rawContent == string.Empty)
                    {
                        fs.Seek(0, SeekOrigin.End);
                    }
                    if (!rawContent.Contains(message) && message.Length > 0)
                    {
                        using (var sw = new StreamWriter(fs))
                        {
                            await sw.WriteLineAsync(message);
                        }
                    }
                }
            }
        }
        
        private static string CheckSymbol(string symbolData) => symbolData.Replace('\u25A1', ' ').Replace(" ", string.Empty);

        private void DisableFileMonitoring()
        {
            var fileAccessAttempts = 0;
            while (fileAccessAttempts < FileAccessAttemptsLimit)
            {
                try
                {
                    _fsWatcher.EnableRaisingEvents = false;
                    break;
                }
                catch
                {
                    fileAccessAttempts++;
                }
            }
            if (fileAccessAttempts > FileAccessAttemptsLimit)
            {
                throw new Exception("Unable to pause file monitoring");
            }
        }

        private void EnableFileMonitoring()
        {
            var fileAccessAttempts = 0;
            while (fileAccessAttempts < FileAccessAttemptsLimit)
            {
                try
                {
                    lock (_locker)
                        _fsWatcher.EnableRaisingEvents = true;
                    break;
                }
                catch
                {
                    fileAccessAttempts++;
                }
            }
            if (fileAccessAttempts > FileAccessAttemptsLimit)
            {
                throw new Exception("Unable to restore file monitoring");
            }
        }

        #endregion

    }
}