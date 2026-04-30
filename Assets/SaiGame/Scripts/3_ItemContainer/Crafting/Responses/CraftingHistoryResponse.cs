using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CraftingHistoryResponse
    {
        public int page;
        public int page_size;
        public int total;
        public CraftingHistoryTransaction[] transactions;
    }
}
