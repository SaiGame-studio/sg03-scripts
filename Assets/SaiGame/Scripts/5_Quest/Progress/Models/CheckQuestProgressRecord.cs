using System;

namespace SaiGame.Services
{
    /// <summary>
    /// The progress snapshot returned by POST .../quests/{questDefinitionId}/check
    /// progress_data is a dynamic object and cannot be deserialized by JsonUtility.
    /// </summary>
    [Serializable]
    public class CheckQuestProgressRecord
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string quest_definition_id;
        // progress_data is a dynamic key-value object; JsonUtility cannot deserialize it.
        // It is extracted manually as a raw JSON string after parsing.
        public string progress_data_json;
        public string status;
        public string completed_at;
        public string claimed_at;
        public string reset_at;
        public int version;
        public string created_at;
        public string updated_at;
    }
}
