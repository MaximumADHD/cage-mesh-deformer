using System.Net;
using System.Text;

var listener = new HttpListener();
listener.Prefixes.Add("http://localhost:20326/asset/");
listener.Prefixes.Add("http://localhost:20326/asset-hash/");
listener.Start();

var http = new HttpClient();
http.DefaultRequestHeaders.Add("UserAgent", "AssetProxy");

while (true)
{
    Console.WriteLine("Waiting for next request...");

    var context = await listener.GetContextAsync();
    var request = context.Request;

    var queryId = request.QueryString["id"];
    var requestPath = request.Url?.AbsolutePath;

    if (long.TryParse(queryId, out long assetId))
    {
        var response = context.Response;
        Console.WriteLine($"Processing {assetId}...");

        var asset = await http.SendAsync(new HttpRequestMessage()
        {
            RequestUri = new Uri($"https://assetdelivery.roblox.com/v1/asset/?id={assetId}"),
            Method = HttpMethod.Get,
        });

        if (asset.StatusCode == HttpStatusCode.OK)
        {
            var output = response.OutputStream;

            var hash = asset.Headers.ETag?
                .ToString()
                .Trim('"');

            if (hash != null)
            {
                if (requestPath == "/asset-hash")
                {
                    using (var writer = new StreamWriter(output))
                    {
                        writer.Write(hash);
                        writer.Close();
                    }

                    response.StatusCode = 200;
                    response.Close();

                    continue;
                }
                else if (requestPath == "/asset")
                {
                    var location = asset.RequestMessage
                        ?.RequestUri
                        ?.ToString();

                    if (location != null)
                    {
                        response.Headers.Add("Location", location);
                        response.StatusCode = 302;
                        response.Close();
                    }

                    continue;
                }
            }

            response.StatusDescription = "Invalid asset";
        }

        response.StatusCode = 400;
        response.Close();
    }
}





