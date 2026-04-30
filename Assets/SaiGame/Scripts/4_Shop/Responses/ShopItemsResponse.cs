using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents the response from the shop items API.
    /// </summary>
    [Serializable]
    public class ShopItemsResponse
    {
        public ShopItemData[] items;
        public int item_count;
        public string shop_id;
    }
}
