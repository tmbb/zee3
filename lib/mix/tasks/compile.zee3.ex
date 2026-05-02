defmodule Mix.Tasks.Compile.Zee3 do
  use Mix.Task

  @shortdoc "Downloads the pre-compiled Z3 binary for the current architecture."

  # A slightly older version for improved compatibility
  # with older versions of libc
  @z3_version "4.13.0"

  @impl Mix.Task
  def run(_args) do
    priv_dir = Path.join(:code.priv_dir(:zee3) || "priv", "bin")
    executable_ext = if match?({:win32, _}, :os.type()), do: ".exe", else: ""
    target_executable = Path.join(priv_dir, "z3" <> executable_ext)

    # Only download if it doesn't already exist
    unless File.exists?(target_executable) do
      Mix.shell().info("Downloading Z3 #{@z3_version} binary...")

      File.mkdir_p!(priv_dir)
      {url, filename} = target_release()

      download_and_extract(url, filename, target_executable)

      Mix.shell().info("Z3 installed at #{target_executable}")
    end

    :ok
  end

  defp target_release do
    arch = to_string(:erlang.system_info(:system_architecture))
    os_type = :os.type()

    base_url = "https://github.com/Z3Prover/z3/releases/download/z3-#{@z3_version}/"

    # Map Erlang OS/Arch to Z3 GitHub Release filenames
    filename =
      case {os_type, arch} do
        # TODO: untested
        {{:unix, :darwin}, "aarch64" <> _} ->
          "z3-#{@z3_version}-arm64-osx-15.7.3.zip"

        # TODO: untested
        {{:unix, :darwin}, _} ->
          "z3-#{@z3_version}-x64-osx-15.7.3.zip"

        {{:unix, :linux}, "aarch64" <> _} ->
          "z3-#{@z3_version}-arm64-glibc-2.35.zip"

        {{:unix, :linux}, _} ->
          "z3-#{@z3_version}-x64-glibc-2.35.zip"

        # TODO: untested
        {{:win32, :nt}, _} ->
          "z3-#{@z3_version}-x64-win.zip"

        _ ->
          Mix.raise(
            "Unsupported architecture for automatic Z3 download: " <>
              "#{os_type} - #{arch}. Please install Z3 manually."
          )
      end

    {base_url <> filename, filename}
  end

  defp download_and_extract(url, zip_name, target_executable) do
    # Ensure standard HTTP/SSL apps are running
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    tmp_dir = System.tmp_dir!()
    zip_path = Path.join(tmp_dir, zip_name)

    # Download following redirects (GitHub releases redirect to S3)
    {:ok, :saved_to_file} =
      :httpc.request(
        :get,
        {String.to_charlist(url), []},
        [autoredirect: true],
        stream: String.to_charlist(zip_path)
      )

    # Extract the zip file into the temp directory
    {:ok, extracted_files} =
      :zip.extract(String.to_charlist(zip_path), cwd: String.to_charlist(tmp_dir))

    # Find the bin/z3 executable inside the extracted folder structure
    z3_path =
      Enum.find(extracted_files, fn path ->
        path_str = to_string(path)
        String.ends_with?(path_str, "/bin/z3") or String.ends_with?(path_str, "/bin/z3.exe")
      end)

    unless z3_path do
      Mix.raise("Could not find Z3 executable in downloaded release.")
    end

    # Move it to our priv/bin directory and make it executable
    File.cp!(to_string(z3_path), target_executable)
    File.chmod!(target_executable, 0o755)

    # Clean up the downloaded zip
    File.rm!(zip_path)
  end
end
