using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A single daily quest pool returned from the pools API.
    /// </summary>
    [Serializable]
    public class DailyQuestPoolData
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string pool_key;
        public string display_name;
        public string description;
        public int slots_per_day;
        public int reset_hour_utc;
        public string assignment_strategy;
        public bool is_active;
        public string created_at;
        public string updated_at;
    }
}
