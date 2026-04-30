using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftRequest
    {
        public string recipe_id;
        public string idempotency_key;
    }
}
