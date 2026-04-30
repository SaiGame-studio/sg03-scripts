using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents the paginated response from the quest chains API.
    /// </summary>
    [Serializable]
    public class ChainQuestResponse
    {
        public ChainQuestData[] chains;
        public int limit;
        public int offset;
        public int total;
    }
}
