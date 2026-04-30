using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Top-level response from a successful purchase.
    /// Endpoint: POST /api/v1/games/{gameId}/shops/{shopId}/purchase
    /// </summary>
    [Serializable]
    public class PurchaseResponse
    {
        public PurchaseRecord purchase_record;
    }
}
