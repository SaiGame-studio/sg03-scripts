using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftingHistoryTransaction
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string recipe_id;
        public string idempotency_key;
        public string status;
        public bool success;
        public bool bonus_triggered;
        public CraftingMaterialItem[] materials_snapshot;
        public CraftingOutputItem[] outputs_snapshot;
        public string created_at;
        public RecipeDetail recipe_detail;
    }
}
