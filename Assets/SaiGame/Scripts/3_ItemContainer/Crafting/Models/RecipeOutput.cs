using System;

namespace SaiGame.Services
{
    [Serializable]
    public class RecipeOutput
    {
        public string id;
        public string recipe_id;
        public string studio_id;
        public string game_id;
        public string item_definition_id;
        public int quantity_min;
        public int quantity_max;
        public string output_type;
        public int sort_order;
        public string created_at;
        public string updated_at;
        public ItemDefinitionData item_definition;
    }
}
