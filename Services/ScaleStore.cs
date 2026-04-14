using System.Collections.Concurrent;
using ScaleApi.DTOs;

namespace ScaleApi.Services;

public interface IScaleStore
{
    ScaleConfigDto? GetConfig(int locationId, int scaleId);
    ScaleValuesDto GetValues(int locationId, int scaleId);
    void SetWeight(int locationId, int scaleId, decimal weight);
    void SetConfig(ScaleConfigDto config);
}

public class ScaleStore : IScaleStore
{
    private readonly ConcurrentDictionary<string, ScaleConfigDto> _configs = new();
    private readonly ConcurrentDictionary<string, decimal> _weights = new();

    private static string Key(int locationId, int scaleId) => $"{locationId}:{scaleId}";

    public ScaleConfigDto? GetConfig(int locationId, int scaleId)
    {
        _configs.TryGetValue(Key(locationId, scaleId), out var config);
        return config;
    }

    public ScaleValuesDto GetValues(int locationId, int scaleId)
    {
        var key = Key(locationId, scaleId);
        _weights.TryGetValue(key, out var weight);
        _configs.TryGetValue(key, out var config);

        var target = config?.Target ?? 0;

        return new ScaleValuesDto
        {
            LocationId = locationId,
            ScaleId = scaleId,
            Weight = weight,
            Target = target,
            Deviation = weight - target
        };
    }

    public void SetWeight(int locationId, int scaleId, decimal weight)
    {
        _weights[Key(locationId, scaleId)] = weight;
    }

    public void SetConfig(ScaleConfigDto config)
    {
        _configs[Key(config.LocationId, config.ScaleId)] = config;
    }
}
