using System;
using System.Globalization;

namespace Cb.Mt4.Driver.Helpers
{
    internal static class MetatraderHelper
    {
        internal static DateTime ParseMtDateTime(this string dateTime)
        {
            return DateTime.ParseExact(dateTime, "yyyy.MM.dd HH:mm:ss", CultureInfo.InvariantCulture);
        }

        internal static string ToMt4DateTime(this DateTime date)
        {
            return date.ToString("yyyy.MM.dd HH:mm");
        }
    }
}
