#!/usr/bin/env ruby
# frozen_string_literal: true
require "json"
require "open3"
require "tmpdir"
require "fileutils"
def run_command(*command)
  output, status = Open3.capture2e(*command)
  abort("Error: #{command.join(" ")} failed: #{output}") unless status.success?
  output
end
def legacy_metadata(repo, asset)
  Dir.mktmpdir("StatusTrioHistory") do |directory|
    dmg = File.join(directory, asset.fetch("name"))
    File.binwrite(dmg, run_command("gh", "api", "repos/#{repo}/releases/assets/#{asset.fetch("id")}", "-H", "Accept: application/octet-stream"))
    mount = File.join(directory, "mount")
    FileUtils.mkdir_p(mount)
    begin
      run_command("hdiutil", "attach", "-quiet", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
      plist = Dir.glob(File.join(mount, "*.app", "Contents", "Info.plist")).first
      abort("Error: historical DMG has no app Info.plist") unless plist
      { "schema_version" => 0, "bundle_id" => run_command("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", plist).strip, "version" => run_command("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", plist).strip, "build" => run_command("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", plist).strip }
    ensure
      system("hdiutil", "detach", "-quiet", mount) if File.directory?(mount)
    end
  end
end
repo = ENV.fetch("RELEASE_REPO")
bundle_id = ENV.fetch("BUNDLE_ID")
build = Integer(ENV.fetch("BUILD"))
fixture = ENV["RELEASE_HISTORY_FIXTURE"]
releases = fixture ? JSON.parse(File.read(fixture)) : JSON.parse(run_command("gh", "api", "--paginate", "--slurp", "repos/#{repo}/releases?per_page=100")).flatten
maximum = nil
releases.each do |release|
  next if release["draft"]
  metadata_asset = release.fetch("assets", []).find { |asset| asset.fetch("name", "").end_with?(".release-metadata.json") }
  metadata = if metadata_asset
    fixture ? metadata_asset.fetch("metadata") : JSON.parse(run_command("gh", "api", "repos/#{repo}/releases/assets/#{metadata_asset.fetch("id")}", "-H", "Accept: application/octet-stream"))
  else
    dmg = release.fetch("assets", []).find { |asset| asset.fetch("name", "").end_with?(".dmg") }
    abort("Error: published release #{release.fetch("tag_name")} lacks metadata and a recoverable DMG") unless dmg
    fixture ? dmg.fetch("metadata") : legacy_metadata(repo, dmg)
  end
  required = %w[schema_version bundle_id version build]
  abort("Error: malformed historical metadata for #{release.fetch("tag_name")}") unless required.all? { |key| metadata.key?(key) } && metadata.fetch("build").to_s.match?(/^[0-9]+$/)
  next unless metadata.fetch("bundle_id") == bundle_id
  maximum = [maximum, metadata.fetch("build").to_i].compact.max
end
abort("Error: build #{build} must exceed published build #{maximum} for #{bundle_id}.") if maximum && build <= maximum
puts JSON.generate(bundle_id: bundle_id, requested_build: build, maximum_published_build: maximum)
