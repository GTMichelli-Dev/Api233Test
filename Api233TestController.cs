using Microsoft.AspNetCore.Mvc;
using ScaleApi.DTOs;
using ScaleApi.Services;

namespace ScaleApi.Controllers;

[ApiController]
[Route("api/api233Test")]
[Produces("application/json")]
public class Api233TestController : ControllerBase
{
    private readonly IScaleStore _store;

    public Api233TestController(IScaleStore store)
    {
        _store = store;
    }

    // ─── GET endpoints ──────────────────────────────────────────────────────────

    /// <summary>Get the configuration for a specific scale.</summary>
    /// <param name="locationId">Location identifier.</param>
    /// <param name="scaleId">Scale identifier.</param>
    /// <response code="200">Config found and returned.</response>
    /// <response code="404">No config exists for this location/scale combination.</response>
    [HttpGet("config")]
    [ProducesResponseType(typeof(ScaleConfigDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public IActionResult GetConfig([FromQuery] int locationId, [FromQuery] int scaleId)
    {
        var config = _store.GetConfig(locationId, scaleId);
        if (config is null)
            return NotFound(new { message = $"No config for location {locationId}, scale {scaleId}." });

        return Ok(config);
    }

    /// <summary>Get the current weight, target, and deviation for a scale.</summary>
    /// <param name="locationId">Location identifier.</param>
    /// <param name="scaleId">Scale identifier.</param>
    /// <response code="200">Values returned. Deviation = Weight - Target.</response>
    [HttpGet("weight")]
    [ProducesResponseType(typeof(ScaleValuesDto), StatusCodes.Status200OK)]
    public IActionResult GetScaleValues([FromQuery] int locationId, [FromQuery] int scaleId)
    {
        var values = _store.GetValues(locationId, scaleId);
        return Ok(values);
    }

    // ─── POST endpoints ─────────────────────────────────────────────────────────

    /// <summary>Post a new weight reading for a scale.</summary>
    /// <remarks>Updates the stored weight and returns the current ScaleValuesDto including calculated deviation.</remarks>
    /// <response code="200">Weight accepted, current values returned.</response>
    /// <response code="400">Invalid request body.</response>
    [HttpPost("weight")]
    [ProducesResponseType(typeof(ScaleValuesDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public IActionResult SetWeight([FromBody] SetWeightRequest request)
    {
        if (request.Weight < 0)
            return BadRequest(new { message = "Weight cannot be negative." });

        _store.SetWeight(request.LocationId, request.ScaleId, request.Weight);
        var values = _store.GetValues(request.LocationId, request.ScaleId);
        return Ok(values);
    }

    /// <summary>Create or update the configuration for a scale.</summary>
    /// <remarks>Overwrites any existing config for the given location/scale combination.</remarks>
    /// <response code="200">Config saved, current config returned.</response>
    /// <response code="400">Invalid request body.</response>
    [HttpPost("config")]
    [ProducesResponseType(typeof(ScaleConfigDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public IActionResult SetScaleConfig([FromBody] SetScaleConfigRequest request)
    {
        if (request.Target < 0)
            return BadRequest(new { message = "Target cannot be negative." });

        var config = new ScaleConfigDto
        {
            LocationId      = request.LocationId,
            ScaleId         = request.ScaleId,
            Target          = request.Target,
            UnderThreshold  = request.UnderThreshold,
            OverThreshold   = request.OverThreshold,
            SubmitThreshold = request.SubmitThreshold
        };

        _store.SetConfig(config);
        return Ok(config);
    }
}
