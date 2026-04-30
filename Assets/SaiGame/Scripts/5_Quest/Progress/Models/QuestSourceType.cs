using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Identifies where the quest list is sourced from.
    /// Extend this enum when new quest types (e.g. Daily) are added.
    /// </summary>
    public enum QuestSourceType
    {
        ChainQuest,
        DailyQuest,
    }
}
