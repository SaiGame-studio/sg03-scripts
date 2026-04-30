using System;

namespace SaiGame.Services
{
    [Serializable]
    public class LeaderboardRankingsResponse
    {
        public LeaderboardRankingEntry[] entries;
        public int limit;
        public int total;
    }
}
