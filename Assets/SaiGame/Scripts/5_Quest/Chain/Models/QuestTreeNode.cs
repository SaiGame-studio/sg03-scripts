using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A single node in the quest chain tree.
    /// Note: JsonUtility supports shallow recursive arrays; deep trees
    /// may require a custom JSON parser (e.g. Newtonsoft.Json).
    /// </summary>
    [Serializable]
    public class QuestTreeNode
    {
        public string quest_id;
        public string quest_name;
        public string status;
        public QuestTreeNode[] children;
    }
}
