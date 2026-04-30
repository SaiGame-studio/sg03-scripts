using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Paginated response from GET /api/v1/games/{gameId}/daily-quest-pools
    /// </summary>
    [Serializable]
    public class DailyQuestPoolsResponse
    {
        public DailyQuestPoolData[] pools;
        public int limit;
        public int offset;
        public int total;
    }
}
