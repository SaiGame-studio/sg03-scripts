using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftingMaterialItem
    {
        public string item_definition_id;
        public string item_definition_name;
        public int quantity;
        public bool was_consumed;
    }
}
