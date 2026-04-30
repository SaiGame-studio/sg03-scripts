using System;

namespace SaiGame.Services
{
    [Serializable]
    public class LeaderboardBoard
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string board_key;
        public string name;
        public string description;
        public string score_mode;
        public string sort_direction;
        public string reset_schedule;
        public string season_id;
        public bool is_active;
        public float max_score_delta;
        public string score_source_type;
        public string score_source_ref_id;
        public string created_at;
        public string updated_at;
    }
}
