using SmartThingsNet.Api;
using SmartThingsNet.Client;
using SmartThingsNet.Model;

namespace SmartThings
{
    class SmartThings
    {
        static void Main()
        {            
            string accesstoken = ""; // Fill your SmartThings access token here
            var configuration = new Configuration();
            configuration.AccessToken = accesstoken;
            var devices = new DevicesApi(configuration);
            var locations = new LocationsApi(configuration);
            var rooms = new RoomsApi(configuration);
            var devicelist = devices.GetDevices(accesstoken).Items;                        

            Console.WriteLine("Locations:");
            Console.WriteLine("- " + String.Join(Environment.NewLine+"- ", locations.ListLocations(accesstoken).Items.Select(x => x.Name)));
            Console.WriteLine();

            Console.WriteLine("Rooms:");
            Console.WriteLine("- " + String.Join(Environment.NewLine+"- ", rooms.ListRooms(accesstoken, locations.ListLocations(accesstoken).Items.First().LocationId.ToString()).Items.Select(x => x.Name)));
            Console.WriteLine();

            Console.WriteLine("Devices:");
            Console.WriteLine("- " + String.Join(Environment.NewLine+"- ", devicelist.Select(x => $"{x.Label} :: {x.DeviceId}").ToList()));
            Console.WriteLine();
        }
    }
}
