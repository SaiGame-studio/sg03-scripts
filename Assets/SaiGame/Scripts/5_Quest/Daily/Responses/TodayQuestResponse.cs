using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Response from GET /api/v1/games/{gameId}/daily-quests/{dqPoolId}
    /// </summary>
    [Serializable]
    public class TodayQuestResponse
    {
        public DailyQuestPoolData pool;
        public DailyQuestEntryData[] entries;
        public DailyStreakData streak;
        public string assigned_date;
    }
}
