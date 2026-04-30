using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Progress snapshot for a single quest definition.
    /// Maps to the "progress" block in GET /api/v1/games/{gameId}/quests/{questDefinitionId}
    /// </summary>
    [Serializable]
    public class QuestProgressSnapshot
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string quest_definition_id;
        // progress_data is a dynamic object – not directly deserializable by JsonUtility
        public string status;
        public string completed_at;
        public string claimed_at;
        public int version;
        public string created_at;
        public string updated_at;
    }
}
