using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Request body for purchasing a shop item.
    /// Endpoint: POST /api/v1/games/{gameId}/shops/{shopId}/purchase
    /// </summary>
    [Serializable]
    public class PurchaseRequest
    {
        public string shop_item_id;
        public int quantity;
        public string idempotency_key;
    }
}
