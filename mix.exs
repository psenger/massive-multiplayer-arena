defmodule MassiveMultiplayerArena.MixProject do
  use Mix.Project

  def project do
    [
      app: :massive_multiplayer_arena,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {MassiveMultiplayerArena.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7.0"},
      {:phoenix_live_view, "~> 0.20.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:libcluster, "~> 3.3"},
      {:ex_machina, "~> 2.7", only: [:test, :dev]},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end
end