using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents the paginated response from the shops API.
    /// </summary>
    [Serializable]
    public class ShopResponse
    {
        public ShopData[] shops;
        public int limit;
        public int offset;
        public int total;
    }
}
