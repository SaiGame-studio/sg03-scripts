using System;

namespace SaiGame.Services
{
    [Serializable]
    public class LeaderboardLocalRankingResponse
    {
        public int rank;
        public string user_id;
        public float score;
        public string metadata;
        public LeaderboardSeason season;
        public string updated_at;
    }
}
