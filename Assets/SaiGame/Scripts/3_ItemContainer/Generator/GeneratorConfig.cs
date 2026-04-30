using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Runtime configuration for a generator, delivered inside definition.metadata.
    /// </summary>
    [Serializable]
    public class GeneratorConfig
    {
        public string collect_destination;
        public GeneratorOutputPool[] output_pool;
        public int production_interval_seconds;
        public int tick_capacity;
    }
}
