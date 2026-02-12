# Stage 1: Build the application
# I use the SDK image to compile the code
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy csproj and restore as distinct layers
COPY ["HelloWorld.csproj", "./"]
RUN dotnet restore "HelloWorld.csproj"

# Copy everything else and build
COPY . .
RUN dotnet publish "HelloWorld.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 2: Run the application
# I use the lighter ASP.NET runtime image for the final container
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "HelloWorld.dll"]