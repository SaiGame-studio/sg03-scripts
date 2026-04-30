using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents a single day in the assign-ahead response,
    /// containing the date metadata and list of assigned quests.
    /// </summary>
    [Serializable]
    public class DailyDayData
    {
        public string date;
        public bool is_today;
        public bool already_assigned;
        public DailyQuestEntryData[] quests;
    }
}
