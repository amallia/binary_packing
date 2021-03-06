#include "CLI/CLI.hpp"
#include "gpu_ic/utils/binary_freq_collection.hpp"
#include "gpu_ic/utils/progress.hpp"
#include "gpu_ic/utils/tight_variable_byte.hpp"
#include "gpu_ic/utils/index.cuh"
#include "gpu_ic/utils/mapper.hpp"
#include "mio/mmap.hpp"
#include "gpu_ic/cuda_bp.cuh"
#include "gpu_ic/cuda_vbyte.cuh"

using namespace gpu_ic;

template <typename InputCollection, typename Decoder>
void verify_index(InputCollection const &input,
                       const std::string &filename, Decoder decoder_function, bool compress_freqs) {

//     Codec codec;
    gpu_ic::index coll;
    mio::mmap_source m;
    std::error_code error;
    m.map(filename, error);
    mapper::map(coll, m);

    {
        progress progress("Verify index", input.size());

        size_t i =0;
        for (auto const &plist : input) {
            auto docs_it = compress_freqs ?  plist.freqs.begin() : plist.docs.begin();

            std::vector<uint32_t> values(plist.docs.size());
            uint32_t last_doc(*docs_it++);;
            for (size_t j = 1; j < plist.docs.size(); ++j) {
                uint32_t doc(*docs_it++);
                if(not compress_freqs) {
                   values[j] = doc - last_doc - 1;
                } else {
                    values[j] = doc - 1;
                }
                last_doc = doc;
            }

            std::vector<uint8_t> tmp;
            auto n = coll.get_data(tmp, i);
            std::vector<uint32_t> decode_values(n);

            CUDA_CHECK_ERROR(cudaSetDevice(0));
            warmUpGPU<<<1, 1>>>();

            uint8_t *  d_encoded;
            CUDA_CHECK_ERROR(cudaMalloc((void **)&d_encoded, tmp.size() * sizeof(uint8_t)));
            CUDA_CHECK_ERROR(cudaMemcpy(d_encoded, tmp.data(), tmp.size() * sizeof(uint8_t), cudaMemcpyHostToDevice));

            uint32_t * d_decoded;
            CUDA_CHECK_ERROR(cudaMalloc((void **)&d_decoded, values.size() * sizeof(uint32_t)));
            decoder_function(d_decoded, d_encoded, decode_values.size());
            CUDA_CHECK_ERROR(cudaMemcpy(decode_values.data(), d_decoded, values.size() * sizeof(uint32_t), cudaMemcpyDeviceToHost));

            cudaFree(d_encoded);
            cudaFree(d_decoded);

            if(n != plist.docs.size())
            {
                std::cerr << "Error: wrong list length. List: " << i << ", size: " << n << ", real_size: " << plist.docs.size() << std::endl;
                std::abort();
            }

            for (size_t j = 0; j < n; ++j) {
                if(decode_values[j] != values[j]) {
                    std::cerr << "Error: wrong decoded value. List: " << i << ", position: " << j << ", element: " << decode_values[j] << ", real_element: " << values[j] << std::endl;
                    std::abort();
                }
            }
            progress.update(1);
            i+=1;
        }
    }

}

template <typename InputCollection, typename Encoder, typename Decoder>
void create_collection(InputCollection const &input,
                       const std::string &output_filename,
                       Encoder &encoder_function, Decoder &decoder_function, bool compress_freqs) {

    typename gpu_ic::index::builder builder(input.num_docs());
    size_t postings = 0;
    {
        progress progress("Create index", input.size());

        for (auto const &plist : input) {
            size_t size = plist.docs.size();
          if(not compress_freqs) {
                builder.add_posting_list(size, plist.docs.begin(), encoder_function, compress_freqs);
            }
            else {
                builder.add_posting_list(size, plist.freqs.begin(), encoder_function, compress_freqs);
            }

            postings += size;
            progress.update(1);
        }
    }

    gpu_ic::index coll;
    auto data_len = builder.build(coll);
    auto byte= mapper::freeze(coll, output_filename.c_str());


    double bits_per_doc  = data_len * 8.0 / postings;
    std::cout << "Documents: " << postings << ", total size bytes: " << byte << ", bits/doc: " << bits_per_doc << std::endl;

    verify_index(input, output_filename, decoder_function, compress_freqs);
}


int main(int argc, char** argv)
{
    std::string type;
    std::string input_basename;
    std::string output_filename;
    bool compress_freqs = false;

    CLI::App app{"compress_index - a tool for compressing an index."};
    app.add_option("-t,--type", type, "Index type")->required();
    app.add_option("-c,--collection", input_basename, "Collection basename")->required();
    app.add_option("-o,--output", output_filename, "Output filename")->required();
    app.add_flag("--freqs", compress_freqs, "Compress freqs instead of docs");
    CLI11_PARSE(app, argc, argv);

    binary_freq_collection input(input_basename.c_str());
    if (type == "cuda_bp") {
        create_collection(input, output_filename, cuda_bp::encode<>, cuda_bp::decode<>, compress_freqs);
    } else if (type == "cuda_bp64") {
        create_collection(input, output_filename, cuda_bp::encode<64>, cuda_bp::decode<64>, compress_freqs);
    } else if (type == "cuda_bp128") {
        create_collection(input, output_filename, cuda_bp::encode<128>, cuda_bp::decode<128>, compress_freqs);
    } else if (type == "cuda_bp256") {
        create_collection(input, output_filename, cuda_bp::encode<256>, cuda_bp::decode<256>, compress_freqs);
    } else if (type == "cuda_bp512") {
        create_collection(input, output_filename, cuda_bp::encode<512>, cuda_bp::decode<512>, compress_freqs);
    } else if (type == "cuda_bp1024") {
        create_collection(input, output_filename, cuda_bp::encode<1024>, cuda_bp::decode<1024>, compress_freqs);
    } else if (type == "cuda_vbyte") {
        create_collection(input, output_filename, cuda_vbyte::encode<>, cuda_vbyte::decode<>, compress_freqs);
    } else if (type == "cuda_vbyte1024") {
        create_collection(input, output_filename, cuda_vbyte::encode<1024>, cuda_vbyte::decode<1024>, compress_freqs);
    } else {
        std::cerr << "Unknown type" << std::endl;
    }

    return 0;
}
