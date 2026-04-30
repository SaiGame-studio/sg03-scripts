using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftingResponse
    {
        public string transaction_id;
        public bool success;
        public bool bonus_triggered;
        public CraftingOutputItem[] output_items;
        public CraftingMaterialItem[] materials_used;
    }
}
