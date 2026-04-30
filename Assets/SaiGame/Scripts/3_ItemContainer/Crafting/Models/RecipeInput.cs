using System;

namespace SaiGame.Services
{
    [Serializable]
    public class RecipeInput
    {
        public string id;
        public string recipe_id;
        public string studio_id;
        public string game_id;
        public string item_definition_id;
        public int quantity;
        public bool is_consumed;
        public string created_at;
        public string updated_at;
        public ItemDefinitionData item_definition;
    }
}
