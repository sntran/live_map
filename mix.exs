defmodule LiveMap.MixProject do
  use Mix.Project

  @source_url "https://github.com/sntran/live_map"
  @version File.read!("VERSION") |> String.trim()

  def project do
    [
      app: :live_map,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      preferred_cli_env: [
        "test.watch": :test
      ],
      test_coverage: [
        ignore_modules: [
          LiveMapTestApp,
          LiveMapTestApp.Application,
          LiveMapTestApp.Endpoint,
          LiveMapTestApp.Router,
          LiveMapTestApp.Router.Helpers,
        ],
      ],
    ]
  end

  defp description do
    """
    LiveMap is a Phoenix LiveView component for interactive map with
    dynamic data.
    """
  end

  defp package do
    [
      name: :live_map,
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE.md",
        "VERSION"
      ],
      maintainers: ["Trần Nguyễn Sơn"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
    ]
  end


  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_live_view, "~> 0.17.5"},
      {:jason, "~> 1.2"},

      # Test/dev deps
      {:plug_cowboy, "~> 2.0", only: :test},
      {:floki, ">= 0.30.0", only: :test},
      {:stream_data, "~> 0.5.0", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # Docs deps
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
    ]
  end

  defp docs do
    [
      main: "LiveMap",
      source_url: @source_url,
      extras: ["README.md"],
    ]
  end
end
