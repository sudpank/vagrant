require "pathname"
require "tmpdir"

require File.expand_path("../../../../base", __FILE__)

describe Vagrant::Action::Builtin::SyncedFolders do
  let(:app) { lambda { |env| } }
  let(:env) { { :machine => machine, :ui => ui } }
  let(:machine) do
    double("machine").tap do |machine|
      machine.stub(:config).and_return(machine_config)
    end
  end

  let(:machine_config) do
    double("machine_config").tap do |top_config|
      top_config.stub(:vm => vm_config)
    end
  end

  let(:vm_config) { double("machine_vm_config") }

  let(:ui) do
    double("ui").tap do |result|
      result.stub(:info)
    end
  end

  subject { described_class.new(app, env) }

  # This creates a synced folder implementation.
  def impl(usable, name)
    Class.new(Vagrant.plugin("2", :synced_folder)) do
      define_method(:name) do
        name
      end

      define_method(:usable?) do |machine|
        usable
      end
    end
  end

  describe "call" do
    let(:synced_folders) { {} }

    before do
      env[:root_path] = Pathname.new(Dir.mktmpdir)
      subject.stub(:synced_folders => synced_folders)
    end

    it "should create on the host if specified" do
      synced_folders[impl(true, "good")] = {
        "root" => {
          hostpath: "foo",
        },

        "other" => {
          hostpath: "bar",
          create: true,
        }
      }

      subject.call(env)

      env[:root_path].join("foo").should_not be_directory
      env[:root_path].join("bar").should be_directory
    end

    it "should invoke prepare then enable" do
      order = []
      sf = Class.new(impl(true, "good")) do
        define_method(:prepare) do |machine, folders|
          order << :prepare
        end

        define_method(:enable) do |machine, folders|
          order << :enable
        end
      end

      synced_folders[sf] = {
        "root" => {
          hostpath: "foo",
        },

        "other" => {
          hostpath: "bar",
          create: true,
        }
      }

      subject.call(env)

      order.should == [:prepare, :enable]
    end
  end

  describe "default_synced_folder_type" do
    it "returns the usable implementation" do
      plugins = {
        "bad" => [impl(false, "bad"), 0],
        "nope" => [impl(true, "nope"), 1],
        "good" => [impl(true, "good"), 5],
      }

      result = subject.default_synced_folder_type(machine, plugins)
      result.new.name.should == "good"
    end
  end

  describe "synced_folders" do
    let(:folders) { {} }
    let(:plugins) { {} }

    before do
      plugins[:default] = [impl(true, "default"), 10]
      plugins[:nfs] = [impl(true, "nfs"), 5]

      subject.stub(:plugins => plugins)
      vm_config.stub(:synced_folders => folders)
    end

    it "should raise exception if bad type is given" do
      folders["root"] = { type: "bad" }

      expect { subject.synced_folders(machine) }.
        to raise_error(StandardError)
    end

    it "should return the proper set of folders" do
      folders["root"] = {}
      folders["nfs"] = { type: "nfs" }

      result = subject.synced_folders(machine)
      result.length.should == 2
      result[plugins[:default][0]].should == { "root" => folders["root"] }
      result[plugins[:nfs][0]].should == { "nfs" => folders["nfs"] }
    end

    it "should ignore disabled folders" do
      folders["root"] = {}
      folders["foo"] = { disabled: true }

      result = subject.synced_folders(machine)
      result.length.should == 1
      result[plugins[:default][0]].length.should == 1
    end
  end
end
