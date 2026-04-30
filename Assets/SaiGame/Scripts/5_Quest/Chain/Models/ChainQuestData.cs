using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents a single quest chain returned from the chains API.
    /// </summary>
    [Serializable]
    public class ChainQuestData
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string chain_key;
        public string display_name;
        public string description;
        public string chain_type;
        public bool is_active;
        public string created_at;
        public string updated_at;
    }
}
