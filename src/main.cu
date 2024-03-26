/*
 * Copyright (c) 2020-2022, NVIDIA CORPORATION.  All rights reserved.
 *
 * NVIDIA CORPORATION and its licensors retain all intellectual property
 * and proprietary rights in and to this software, related documentation
 * and any modifications thereto.  Any use, reproduction, disclosure or
 * distribution of this software and related documentation without an express
 * license agreement from NVIDIA CORPORATION is strictly prohibited.
 */

/** @file   main.cu
 *  @author Thomas Müller, NVIDIA
 */

#include <neural-graphics-primitives/testbed.h>

#include <tiny-cuda-nn/common.h>

#include <args/args.hxx>

#include <filesystem/path.h>

using namespace args;
using namespace ngp;
using namespace std;
using namespace tcnn;
namespace fs = ::filesystem;

int main(int argc, char** argv) {
    ArgumentParser parser{
            "neural graphics primitives\n"
            "version " NGP_VERSION,
            "",
    };

    HelpFlag help_flag{
            parser,
            "HELP",
            "Display this help menu.",
            {'h', "help"},
    };

    ValueFlag<string> mode_flag{
            parser,
            "MODE",
            "Mode can be 'nerf', 'sdf', 'image', or 'volume' or 'normal",
            {'m', "mode"},
    };


	Flag lone_flag{
            parser,
            "LONE",
            "Activate lone between normals !",
            {'l',"lone"},
    };

    ValueFlag<string> network_config_flag{
            parser,
            "CONFIG",
            "Path to the network config. Uses the scene's default if unspecified.",
            {'n', 'c', "network", "config"},
    };

    Flag no_gui_flag{
            parser,
            "NO_GUI",
            "Disables the GUI and instead reports training progress on the command line.",
            {"no-gui"},
    };

    Flag save_mesh_flag{
            parser,
            "SAVE_MESH",
            "Save as a mesh when it's done.",
            {"save-mesh"},
    };

	Flag save_snapshot_flag{
            parser,
            "SAVE_SNAPSHOT",
            "Save as a snapshot when it's done.",
            {"save-snapshot"},
    };

	Flag opti_lights_flag{
            parser,
            "OPTI-LIGHTS",
            "Use optimal lights per pixels",
            {"opti-lights"},
    };

    Flag no_train_flag{
            parser,
            "NO_TRAIN",
            "Disables training on startup.",
            {"no-train"},
    };

    ValueFlag<string> scene_flag{
            parser,
            "SCENE",
            "The scene to load. Can be NeRF dataset, a *.obj mesh for training a SDF, an image, or a *.nvdb volume.",
            {'s', "scene"},
    };

    ValueFlag<string> snapshot_flag{
            parser,
            "SNAPSHOT",
            "Optional snapshot to load upon startup.",
            {"snapshot"},
    };

    ValueFlag<uint32_t> width_flag{
            parser,
            "WIDTH",
            "Resolution width of the GUI.",
            {"width"},
    };

    ValueFlag<uint32_t> height_flag{
            parser,
            "HEIGHT",
            "Resolution height of the GUI.",
            {"height"},
    };

    ValueFlag<uint32_t> max_iter_flag{
            parser,
            "MAXITER",
            "Maximum number of iterations.",
            {"maxiter"},
    };

    Flag version_flag{
            parser,
            "VERSION",
            "Display the version of neural graphics primitives.",
            {'v', "version"},
    };

	ValueFlag<float> mask_weight_flag{
            parser,
            "MASK_WEIGHT",
            "Mask weight.",
            {"mask-weight"},
    };

	

	// Parse command line arguments and react to parsing
	// errors using exceptions.
	try {
		parser.ParseCLI(argc, argv);
	} catch (const Help&) {
		cout << parser;
		return 0;
	} catch (const ParseError& e) {
		cerr << e.what() << endl;
		cerr << parser;
		return -1;
	} catch (const ValidationError& e) {
		cerr << e.what() << endl;
		cerr << parser;
		return -2;
	}

	if (version_flag) {
		tlog::none() << "neural graphics primitives version " NGP_VERSION;
		return 0;
	}

	try {
		ETestbedMode mode;
		if (!mode_flag) {
            tlog::error() << "You need to specify --mode {sdf,nerf,image,volume}";
            return 1;
		} else {
			auto mode_str = get(mode_flag);
			if (equals_case_insensitive(mode_str, "nerf")) {
				mode = ETestbedMode::Nerf;
			} else if (equals_case_insensitive(mode_str, "sdf")) {
				mode = ETestbedMode::Sdf;
			} else if (equals_case_insensitive(mode_str, "image")) {
				mode = ETestbedMode::Image;
			} else if (equals_case_insensitive(mode_str, "volume")) {
				mode = ETestbedMode::Volume;
			} else {
				tlog::error() << "Mode must be 'nerf'";
				return 1;
			}
		}

		Testbed testbed{mode};
        if (max_iter_flag){
            testbed.set_max_iter(get(max_iter_flag));
        }

		if (lone_flag){
            testbed.apply_L1();
        }

		if (opti_lights_flag){
			testbed.apply_light_opti();
		}

        tlog::info() << "Number of iterations : " << testbed.get_max_iter();

		if (scene_flag) {
			fs::path scene_path = get(scene_flag);
			if (!scene_path.exists()) {
				tlog::error() << "Scene path " << scene_path << " does not exist.";
				return 1;
			}
			testbed.load_training_data(scene_path.str());
		}

		std::string mode_str;
		switch (mode) {
			case ETestbedMode::Nerf:   mode_str = "nerf";   break;
			case ETestbedMode::Sdf:    mode_str = "sdf";    break;
			case ETestbedMode::Image:  mode_str = "image";  break;
			case ETestbedMode::Volume: mode_str = "volume"; break;
		}

		if (snapshot_flag) {
			// Load network from a snapshot if one is provided
			fs::path snapshot_path = get(snapshot_flag);
			if (!snapshot_path.exists()) {
				tlog::error() << "Snapshot path " << snapshot_path << " does not exist.";
				return 1;
			}

			testbed.load_snapshot(snapshot_path.str());
			testbed.m_train = true;
			printf("*******Loaded snapshot succeed!\n");
		} else {
			// Otherwise, load the network config and prepare for training
			fs::path network_config_path = fs::path{"configs"}/mode_str;
			if (network_config_flag) {
				auto network_config_str = get(network_config_flag);
				if ((network_config_path/network_config_str).exists()) {
					network_config_path = network_config_path/network_config_str;
				} else {
					network_config_path = network_config_str;
				}
			} else {
				network_config_path = network_config_path/"base.json";
			}

			if (!network_config_path.exists()) {
				tlog::error() << "Network config path " << network_config_path << " does not exist.";
				return 1;
			}
			tlog::info() << "ICI1";
			testbed.reload_network_from_file(network_config_path.str());
			tlog::info() << "ICI2";
			testbed.m_train = !no_train_flag;
			tlog::info() << "ICI3";
		}

		bool gui = !no_gui_flag;
#ifndef NGP_GUI
		gui = false;
#endif

		if (gui) {
			testbed.init_window(width_flag ? get(width_flag) : 1920, height_flag ? get(height_flag) : 1080);
		}

		if (mask_weight_flag){
            testbed.set_mask_weight(get(mask_weight_flag));
        }

		// Render/training loop
		while (testbed.frame()) {
			if (!gui) {
				tlog::info() << "iteration=" << testbed.m_training_step << " loss=" << testbed.m_loss_scalar.val();
				// tlog::info() << "iteration=" << testbed.m_training_step << " loss=" << testbed.m_loss_scalar.val() << " lr=" << testbed.m_optimizer.learning_rate();
			}
		}

        std::string path = get(scene_flag);
        size_t found = path.find_last_of("/\\");
        std::string folder_name = path.substr(0,found);

        static char obj_filename_buf[128] = "";
        if (obj_filename_buf[0] == '\0') {
            snprintf(obj_filename_buf, sizeof(obj_filename_buf), "%s", (folder_name+"/mesh_"+to_string(testbed.get_max_iter())+"_.obj").c_str());
        }

        if (save_mesh_flag){
			tlog::info() << "SAVING";
            testbed.compute_and_save_marching_cubes_mesh(obj_filename_buf,Eigen::DenseBase<Eigen::Vector3i>::Constant(1024),{},0.0f,false);
        }

		std::string  snpashot_filename = folder_name +"/snapshot_"+to_string(testbed.get_max_iter())+".msgpack";
        

		if(save_snapshot_flag){
			tlog::info() << "Saving Snapshot !";
			tlog::info() << snpashot_filename;
			testbed.save_snapshot(snpashot_filename,false);
		}


	} catch (const exception& e) {
		tlog::error() << "Uncaught exception: " << e.what();
		return 1;
	}
}