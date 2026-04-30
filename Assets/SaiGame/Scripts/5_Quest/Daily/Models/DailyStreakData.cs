using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Streak record returned inside the today-quest response.
    /// </summary>
    [Serializable]
    public class DailyStreakData
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string pool_id;
        public int current_streak;
        public int longest_streak;
        public int total_completions;
        public int version;
        public string created_at;
        public string updated_at;
    }
}
