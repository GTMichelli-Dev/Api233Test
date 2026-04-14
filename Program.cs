using System.Reflection;
using ScaleApi.Services;

var builder = WebApplication.CreateBuilder(args);

// ─── Services ────────────────────────────────────────────────────────────────

builder.Services.AddControllers();
builder.Services.AddSingleton<IScaleStore, ScaleStore>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new()
    {
        Title   = "api233Test",
        Version = "v1",
        Description = "Real-time weight and configuration API for TSS/msTechnologies scale systems.\n\n" +
                      "**Deviation** is calculated as `Weight - Target`. Negative = under, positive = over."
    });

    // Pull XML comments into Swagger UI
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath))
        options.IncludeXmlComments(xmlPath);
});

// Kestrel: listen on both HTTP (redirect) and HTTPS
// Certificate paths are configured in appsettings.json
builder.WebHost.ConfigureKestrel((context, options) =>
{
    var kestrelSection = context.Configuration.GetSection("Kestrel");
    options.Configure(kestrelSection);
});

// ─── Pipeline ────────────────────────────────────────────────────────────────

var app = builder.Build();

// Always expose Swagger — restrict by IP in Nginx if needed
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "api233Test v1");
    options.RoutePrefix = string.Empty;
    options.DocumentTitle = "api233Test";
    options.DefaultModelsExpandDepth(2);
    options.DefaultModelRendering(Swashbuckle.AspNetCore.SwaggerUI.ModelRendering.Model);
});

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
