/**
 * Copyright 2018-present Antonio Mallia <me@antoniomallia.it>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <gmock/gmock.h>
#include <gtest/gtest.h>
#include <cuda.h>

#include "synthetic/uniform.hpp"
#include "benchmark/benchmark.h"

#include "bp/cuda_bp.cuh"
#include "bp/cuda_common.hpp"

__global__
void warmUpGPU()
{
  // do nothing
}

class RandomValuesFixture : public ::benchmark::Fixture {

    static std::vector<uint32_t> generate_random_vector(size_t n) {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::vector<uint32_t> values(n);
        std::uniform_int_distribution<> dis(uint32_t(0));
        std::generate(values.begin(), values.end(), [&](){ return dis(gen); });
        return values;
    }

public:
    using ::benchmark::Fixture::SetUp;
    using ::benchmark::Fixture::TearDown;

    virtual void SetUp(::benchmark::State& st) {
        values = generate_random_vector(st.range(0));
        encoded_values.resize(values.size() * 8);
        auto compressedsize = cuda_bp::encode(encoded_values.data(), values.data(), values.size());
        encoded_values.resize(compressedsize);
        encoded_values.shrink_to_fit();

        decoded_values.resize(values.size());

        CUDA_CHECK_ERROR(cudaSetDevice(3));
        warmUpGPU<<<1, 1>>>();

    }

    virtual void TearDown(::benchmark::State&) {
        ASSERT_EQ(decoded_values.size(), values.size());
        for (size_t i = 0; i < values.size(); ++i)
        {
            ASSERT_EQ(decoded_values[i], values[i]);
        }
        values.clear();
        encoded_values.clear();
        decoded_values.clear();
    }
    std::vector<uint32_t> values;
    std::vector<uint8_t> encoded_values;
    std::vector<uint32_t> decoded_values;
};


BENCHMARK_DEFINE_F(RandomValuesFixture, decode)(benchmark::State& state) {
    while (state.KeepRunning()) {
        cuda_bp::decode(decoded_values.data(), encoded_values.data(), decoded_values.size());
    }
    auto bpi = double(8*encoded_values.size())/decoded_values.size();
    state.counters["bpi"] = benchmark::Counter(bpi, benchmark::Counter::kAvgThreads);
}
BENCHMARK_REGISTER_F(RandomValuesFixture, decode)->Range(1ULL<<14, 1ULL<<28);

BENCHMARK_MAIN();
