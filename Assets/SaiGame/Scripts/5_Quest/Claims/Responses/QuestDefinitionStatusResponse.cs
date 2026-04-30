using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Response from GET /api/v1/games/{gameId}/quests/{questDefinitionId}
    /// Returns current progress + quest definition + rolled-up status.
    /// </summary>
    [Serializable]
    public class QuestDefinitionStatusResponse
    {
        public QuestProgressSnapshot progress;
        public QuestDefinitionData quest_definition;
        public string status;
    }
}
