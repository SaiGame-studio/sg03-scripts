using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftByKeyRequest
    {
        public string recipe_key;
        public string idempotency_key;
    }
}
