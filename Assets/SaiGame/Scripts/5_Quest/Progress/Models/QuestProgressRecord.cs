using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Server response for POST /api/v1/games/{gameId}/quests/{questDefinitionId}/start
    /// </summary>
    [Serializable]
    public class QuestProgressRecord
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string quest_definition_id;
        public string status;
        public int version;
        public string created_at;
        public string updated_at;
        // progress_data is a dynamic object; stored as raw JSON string if needed
    }
}
