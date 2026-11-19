#!/usr/bin/env ruby
# Exercise failures in a disposable fixture, never by editing component versions.
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

root = File.expand_path("..", __dir__)
checks = 0
verify = lambda do |name, &block|
  raise "FAIL: #{name}" unless block.call
  checks += 1
  puts "PASS: #{name}"
end

Dir.mktmpdir("xlib-release-check-") do |fixture|
  paths = %w[
    scripts/release-check.sh releases/0.11.0.yaml releases/0.12.0.yaml contracts/openapi.yaml
    docs/architecture/migrator-retirement-plan.json
    apps/android/version.properties apps/ios/XLibReader.xcodeproj/project.pbxproj
    apps/ios/XLibReader/Resources/Info.plist services/backend/package.json
  ]
  paths.each do |path|
    target = File.join(fixture, path)
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(root, path), target)
  end
  script = File.join(fixture, "scripts/release-check.sh")
  # Historical retirement-policy cases must not depend on the current app version.
  # Normalize only disposable copies; retain the live build numbers for drift checks.
  android_path = File.join(fixture, "apps/android/version.properties")
  File.write(android_path, File.read(android_path).sub(/^versionName=.+$/, "versionName=0.11.0"))
  project_path = File.join(fixture, "apps/ios/XLibReader.xcodeproj/project.pbxproj")
  File.write(project_path, File.read(project_path).gsub(/MARKETING_VERSION = [^;]+;/, "MARKETING_VERSION = 0.11.0;"))
  backend_path = File.join(fixture, "services/backend/package.json")
  historical = YAML.safe_load(File.read(File.join(fixture, "releases/0.11.0.yaml")), aliases: false)
  backend = JSON.parse(File.read(backend_path))
  backend["version"] = historical.fetch("components").fetch("backend").fetch("version").to_s
  File.write(backend_path, JSON.pretty_generate(backend) + "\n")
  fixture_before = paths.to_h { |path| [path, File.binread(File.join(fixture, path))] }
  run = lambda do |environment, *args|
    output, status = Open3.capture2e({"RELEASE_VERSION" => "0.11.0"}.merge(environment),
                                   "sh", script, *args)
    [status.success?, output]
  end
  manifest_path = File.join(fixture, "releases/0.11.0.yaml")
  original = File.read(manifest_path)
  verify.call("explicit inspection mode allows build numbers to advance beyond the release manifest") do
    run.call({"IGNORE_BUILD_NUMBERS" => "1"})[0]
  end

  manifest = YAML.safe_load(original, aliases: false)
  android_properties = File.read(File.join(fixture, "apps/android/version.properties"))
  manifest.fetch("components").fetch("android")["version_code"] =
    android_properties[/^versionCode=(\d+)$/, 1].to_i
  project = File.read(File.join(fixture, "apps/ios/XLibReader.xcodeproj/project.pbxproj"))
  manifest.fetch("components").fetch("ios")["build_number"] =
    project.scan(/CURRENT_PROJECT_VERSION = ([^;]+);/).flatten.uniq.fetch(0)
  File.write(manifest_path, YAML.dump(manifest))
  strict_manifest = File.read(manifest_path)
  verify.call("strict release check matches component versions and build numbers") { run.call({})[0] }
  verify.call("environment selects manifest and missing manifest fails") do
    success, output = run.call({"RELEASE_VERSION" => "missing"})
    !success && output.include?("release manifest not found")
  end
  verify.call("explicit argument takes precedence over environment") do
    run.call({"RELEASE_VERSION" => "missing"}, "0.11.0")[0]
  end

  [
    ["android", "version_name", "0.0.0", "Android version_name mismatch"],
    ["android", "version_code", -1, "Android version_code mismatch"],
    ["ios", "marketing_version", "0.0.0", "iOS marketing_version mismatch"],
    ["ios", "build_number", -1, "iOS build_number mismatch"],
    ["backend", "version", "0.0.0", "Backend version mismatch"]
  ].each do |component, field, value, expected|
    manifest = YAML.safe_load(strict_manifest, aliases: false)
    manifest.fetch("components").fetch(component)[field] = value
    File.write(manifest_path, YAML.dump(manifest))
    verify.call("reject #{component}.#{field} mismatch") do
      success, output = run.call({})
      !success && output.include?(expected)
    end
  end
  File.write(manifest_path, strict_manifest)
  [
    ["contains_legacy_migrator", true, "Migrator retirement release cannot contain legacy migrator"],
    ["minimum_direct_from", "0.9.0", "Post-migrator release minimum source mismatch"],
    ["required_intermediate", "0.9.0", "Post-migrator release intermediate mismatch"]
  ].each do |field, value, expected|
    manifest = YAML.safe_load(strict_manifest, aliases: false)
    manifest.fetch("upgrade").fetch("local_storage")[field] = value
    File.write(manifest_path, YAML.dump(manifest))
    verify.call("reject invalid local storage upgrade #{field}") do
      success, output = run.call({})
      !success && output.include?(expected)
    end
  end
  File.write(manifest_path, original)
  verify.call("checking does not rewrite the manifest or component versions") do
    success, = run.call({"IGNORE_BUILD_NUMBERS" => "1"})
    success && paths.all? { |path| fixture_before.fetch(path) == File.binread(File.join(fixture, path)) }
  end
end

# A parent `make check RELEASE=...` exports command-line overrides in MAKEFLAGS.
# Each regression invocation must control its own selection, not inherit those.
make_environment = {"MAKEFLAGS" => nil, "MFLAGS" => nil, "MAKEOVERRIDES" => nil,
                    "GNUMAKEFLAGS" => nil, "RELEASE_VERSION" => nil, "RELEASE" => nil}
verify.call("make check does not implicitly select a historical release manifest") do
  output, status = Open3.capture2e(make_environment,
                                 "make", "-n", "check", chdir: root)
  status.success? && output.include?('RELEASE_VERSION="" ./scripts/check-local.sh')
end

verify.call("make check honors explicit RELEASE_VERSION") do
  output, status = Open3.capture2e(make_environment.merge("RELEASE_VERSION" => "fixture"),
                                 "make", "-n", "check", chdir: root)
  status.success? && output.include?('RELEASE_VERSION="fixture"')
end

verify.call("make check explicit RELEASE overrides RELEASE_VERSION") do
  output, status = Open3.capture2e(make_environment.merge("RELEASE_VERSION" => "other"),
                                 "make", "-n", "check", "RELEASE=fixture", chdir: root)
  status.success? && output.include?('RELEASE_VERSION="fixture"')
end

verify.call("make check-alpha retains its strict release default") do
  output, status = Open3.capture2e(make_environment,
                                 "make", "-n", "check-alpha", chdir: root)
  status.success? && output.include?('RELEASE_VERSION="0.12.0"')
end

verify.call("development entry only checks explicitly selected releases, without ignoring builds") do
  local_script = File.read(File.join(root, "scripts/check-local.sh"))
  alpha_script = File.read(File.join(root, "scripts/check-alpha.sh"))
  local_script.include?('if [ -n "${RELEASE_VERSION:-}" ]; then') &&
    local_script.include?('"$root/scripts/release-check.sh" "$RELEASE_VERSION"') &&
    !local_script.include?("IGNORE_BUILD_NUMBERS") &&
    alpha_script.include?('RELEASE_VERSION="$release_version" "$root/scripts/check-local.sh"')
end

%w[check check-alpha].each do |target|
  verify.call("make #{target} forwards explicit RELEASE") do
    output, status = Open3.capture2e(make_environment, "make", "-n", target, "RELEASE=fixture", chdir: root)
    status.success? && output.include?('RELEASE_VERSION="fixture"')
  end
end
puts "#{checks} release-check regression checks passed"
