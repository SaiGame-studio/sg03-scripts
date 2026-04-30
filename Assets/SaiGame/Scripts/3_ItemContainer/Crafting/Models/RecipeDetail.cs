using System;

namespace SaiGame.Services
{
    [Serializable]
    public class RecipeDetail
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string recipe_key;
        public string name;
        public string description;
        public string category;
        public int success_rate;
        public int bonus_rate;
        public bool is_active;
        public RecipeMetadata metadata;
        public string created_by;
        public string created_at;
        public string updated_at;
        public RecipeInput[] inputs;
        public RecipeOutput[] outputs;
    }
}
