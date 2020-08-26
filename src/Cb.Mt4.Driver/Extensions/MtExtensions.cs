using System;
using System.ComponentModel;

namespace Cb.Mt4.Driver.Extensions 
{
    public static class MtExtensions
    {
        public static string GetDescription(this Enum enumValue)
        {
            return enumValue.GetType().GetCustomAttributes(typeof(DescriptionAttribute), false)[0].ToString();
        }
    }
}