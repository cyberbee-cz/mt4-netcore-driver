using System;
using System.Globalization;
using System.Linq;
using Cb.Mt4.Driver.Extensions;

namespace Cb.Mt4.Driver.Helpers
{
    internal static class MtCommHelper
    {
        internal const string NewLineSeparator = "\\el";
        internal const string NewMessageSeparator = "\\el";
        internal const char CommSeparatorChar = ';';

        internal static string[] GetCommandData(Enum command, string message)
        {
            if(message.Contains("{0}"))
            {
                return
                    message.Replace(command.GetDescription().Split(new[] {"{0}"}, StringSplitOptions.None)[0],
                        string.Empty).Split(CommSeparatorChar).Select(val => val.Trim()).ToArray();
            }
            return
                message.Replace(command.GetDescription() + CommSeparatorChar, string.Empty)
                    .Split(CommSeparatorChar)
                    .Select(val => val.Trim().Replace("\0", string.Empty))
                    .ToArray();
        }

        internal static string CreateCommandMessage(Enum command, params object[] payload)
        {
            string commandMessage = command.GetDescription();
            if (payload != null)
            {
                foreach (object data in payload)
                {
                    string formattedData = "";
                    if (data == null)
                    {
                        formattedData = string.Empty;
                    }
                    else if (data is DateTime)
                    {
                        formattedData = ((DateTime) data).ToMt4DateTime();
                    }
                    else if (data is double)
                    {
                        formattedData = ((double)data).ToString(CultureInfo.InvariantCulture);
                    }
                    else
                    {
                        formattedData = data.ToString();
                    }
                    commandMessage += CommSeparatorChar + formattedData;
                }
            }
            return commandMessage;
        }

        internal static string CreateCommandMessage(Enum command, string payloadString)
        {
            return command.GetDescription() + CommSeparatorChar.ToString() + payloadString;
        }
    }
}
