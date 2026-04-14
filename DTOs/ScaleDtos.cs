namespace ScaleApi.DTOs;

public class ScaleConfigDto
{
    public int LocationId { get; set; }
    public int ScaleId { get; set; }
    public decimal Target { get; set; }
    public decimal UnderThreshold { get; set; }
    public decimal OverThreshold { get; set; }
    public decimal SubmitThreshold { get; set; }
}

public class ScaleValuesDto
{
    public int LocationId { get; set; }
    public int ScaleId { get; set; }
    public decimal Weight { get; set; }
    public decimal Target { get; set; }
    public decimal Deviation { get; set; }
}

public class SetWeightRequest
{
    public int LocationId { get; set; }
    public int ScaleId { get; set; }
    public decimal Weight { get; set; }
}

public class SetScaleConfigRequest
{
    public int LocationId { get; set; }
    public int ScaleId { get; set; }
    public decimal Target { get; set; }
    public decimal UnderThreshold { get; set; }
    public decimal OverThreshold { get; set; }
    public decimal SubmitThreshold { get; set; }
}
