using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftingOutputItem
    {
        public string item_definition_id;
        public string item_definition_name;
        public int quantity;
    }
}
