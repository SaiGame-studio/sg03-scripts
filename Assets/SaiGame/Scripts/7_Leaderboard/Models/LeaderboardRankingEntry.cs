using System;

namespace SaiGame.Services
{
    [Serializable]
    public class LeaderboardRankingEntry
    {
        public int rank;
        public string user_id;
            public string display_name;
        public float score;
        public string metadata;
        public string updated_at;
    }
}
