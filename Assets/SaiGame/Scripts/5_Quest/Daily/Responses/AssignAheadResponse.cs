using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Full response from POST /api/v1/games/{gameId}/daily-quests/{dqPoolId}/assign-ahead
    /// </summary>
    [Serializable]
    public class AssignAheadResponse
    {
        public string pool_id;
        public int days_ahead;
        public string start_date;
        public string end_date;
        public DailyDayData[] days;
    }
}
