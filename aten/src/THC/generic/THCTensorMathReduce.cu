#ifndef THC_GENERIC_FILE
#define THC_GENERIC_FILE "generic/THCTensorMathReduce.cu"
#else

THC_API void
THCTensor_(sum)(THCState* state, THCTensor *self, THCTensor *src, int dimension, int keepdim) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  if (!THC_reduceDim<real>(state, self, src,
                           thrust::identity<accreal>{},
                           ReduceAdd<accreal>{},
                           thrust::identity<accreal>{},
                           scalar_cast<accreal>(0),
                           dimension,
                           keepdim)) {
    THArgCheck(false, 2, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
}

THC_API void
THCTensor_(prod)(THCState* state, THCTensor *self, THCTensor *src, int dimension, int keepdim) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  if (!THC_reduceDim<real>(state, self, src,
                           thrust::identity<accreal>{},
                           ReduceMultiply<accreal>{},
                           thrust::identity<accreal>{},
                           scalar_cast<accreal>(1),
                           dimension,
                           keepdim)) {
    THArgCheck(false, 2, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
}

THC_API void
THCTensor_(mean)(THCState *state, THCTensor *self, THCTensor *src, int dim, int keepdim)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  const accreal size = scalar_cast<accreal>(THCTensor_(size)(state, src, dim));
  if (!THC_reduceDim<real>(state, self, src,
                           thrust::identity<accreal>{},
                           ReduceAdd<accreal>{},
                           ReduceDivide<accreal>{size},
                           scalar_cast<accreal>(0),
                           dim,
                           keepdim)) {
    THArgCheck(false, 2, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
}

#if defined(THC_REAL_IS_FLOAT) || defined(THC_REAL_IS_DOUBLE) || defined(THC_REAL_IS_HALF)

THC_API void
THCTensor_(renorm)(THCState *state, THCTensor* self, THCTensor* src, real value, int dimension, real maxnorm)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  THCTensor *self_;
  THCTensor *src_ = THCTensor_(newTranspose)(state, src, dimension, 0);
  THCTensor *data = THCTensor_(newClone)(state, src_);
  int64_t numel = THCTensor_(nElement)(state, data);

  THArgCheck(dimension >= 0 && dimension < THCTensor_(nDimensionLegacyNoScalars)(state, src), 3, "invalid dimension");
  THArgCheck(THCNumerics<real>::gt(value, scalar_cast<real>(0)), 2, "non-positive-norm not supported");
  THArgCheck(THCTensor_(nDimensionLegacyNoScalars)(state, src) > 1, 1, "need at least 2 dimensions");

  if (numel > 0) {
    ptrdiff_t size = numel / THTensor_sizeLegacyNoScalars(data, 0);
    dim3 grid( THTensor_sizeLegacyNoScalars(data, 0));
    dim3 threads(32);

    THCTensor_kernel_renorm<real, accreal>
      <<<grid, threads, 0, THCState_getCurrentStream(state)>>>
      (THCTensor_(data)(state, data), scalar_cast<accreal>(value), size, scalar_cast<accreal>(maxnorm));

    cudaError errcode = cudaGetLastError();
    if(errcode != cudaSuccess)
      THError(cudaGetErrorString(errcode));
  }

  THCTensor_(free)(state, src_);
  self_ = THCTensor_(newTranspose)(state, data, dimension, 0);
  THCTensor_(resizeAs)(state, self, self_);
  THCTensor_(freeCopyTo)(state, self_, self);
  THCTensor_(free)(state, data);
}

THC_API void
THCTensor_(std)(THCState *state, THCTensor *self_, THCTensor *src, int dimension, int biased, int keepdim)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self_, src));

  THCTensor_preserveReduceDimSemantics(
      state, self_, THCTensor_(nDimensionLegacyAll)(state, src), dimension, keepdim);
  std::vector<int64_t> dim = THTensor_sizesLegacyNoScalars(src);
  dim[dimension] = 1;
  THCTensor_(resize)(state, self_, dim, {});

  THCTensor *self = THCTensor_(newContiguous)(state, self_);
  src = THCTensor_(newContiguous)(state, src);

  if (dimension == THCTensor_(nDimensionLegacyAll)(state, src) - 1) {
    THCTensor_varInnermostDim<THCTensor, real, accreal, true>(state, self, src, biased);
  } else {
    THCTensor_varOuterDim<THCTensor, real, accreal, true>(state, self, src, dimension, biased);
  }

  THCTensor_(free)(state, src);
  THCTensor_(freeCopyTo)(state, self, self_);

  if (!keepdim) {
    THCTensor_(squeeze1d)(state, self_, self_, dimension);
  }
}

THC_API void
THCTensor_(var)(THCState *state, THCTensor *self_, THCTensor *src, int dimension, int biased, int keepdim)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self_, src));

  THCTensor_preserveReduceDimSemantics(
      state, self_, THCTensor_(nDimensionLegacyAll)(state, src), dimension, keepdim);
  std::vector<int64_t> dim = THTensor_sizesLegacyNoScalars(src);
  dim[dimension] = 1;
  THCTensor_(resize)(state, self_, dim, {});

  THCTensor *self = THCTensor_(newContiguous)(state, self_);
  src = THCTensor_(newContiguous)(state, src);

  if (dimension == THCTensor_(nDimensionLegacyAll)(state, src) - 1) {
    THCTensor_varInnermostDim<THCTensor, real, accreal, false>(state, self, src, biased);
  } else {
    THCTensor_varOuterDim<THCTensor, real, accreal, false>(state, self, src, dimension, biased);
  }

  THCTensor_(free)(state, src);
  THCTensor_(freeCopyTo)(state, self, self_);

  if (!keepdim) {
    THCTensor_(squeeze1d)(state, self_, self_, dimension);
  }
}

THC_API accreal
THCTensor_(stdall)(THCState *state, THCTensor *self, int biased)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  return THCNumerics<accreal>::sqrt((THCTensor_(varall)(state, self, biased)));
}

THC_API accreal
THCTensor_(varall)(THCState *state, THCTensor *self, int biased)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal mean = THCTensor_(meanall)(state, self);

  accreal val;
  if (!THC_reduceAll<real>(state, self,
                           SquareFunctor<accreal>(mean),
                           ReduceAdd<accreal>(),
                           scalar_cast<accreal>(0),
                           &val, 0)) {
    THArgCheck(false, 1, CUTORCH_DIM_WARNING);
  }

  val = THCNumerics<accreal>::div(
    val,
    scalar_cast<accreal>(std::max<int64_t>(0, THCTensor_(nElement)(state, self) - (biased ? 0 : 1)))
  );

  THCudaCheck(cudaGetLastError());
  return val;
}

THC_API void
THCTensor_(norm)(THCState *state, THCTensor* self, THCTensor* src, real _value, int dimension, int keepdim)
{
  const accreal value = scalar_cast<accreal>(_value);
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(0))) {
    THC_reduceDim<real>(state, self, src,
                        TensorNonZeroOp<accreal>{},
                        ReduceAdd<accreal>{},
                        thrust::identity<accreal>{},
                        scalar_cast<accreal>(0),
                        dimension, keepdim);
  } else if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(1))) {
    THC_reduceDim<real>(state, self, src,
                        TensorNormOp<accreal, 1>{value},
                        ReduceAdd<accreal>{},
                        thrust::identity<accreal>{},
                        scalar_cast<accreal>(0),
                        dimension, keepdim);
  } else if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(2))) {
    THC_reduceDim<real>(state, self, src,
                        TensorNormOp<accreal, 2>{value},
                        ReduceAdd<accreal>{},
                        ReducePow<accreal>{scalar_cast<accreal>(.5)},
                        scalar_cast<accreal>(0),
                        dimension, keepdim);
  } else if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(INFINITY))) {
    THC_reduceDim<real>(state, self, src,
                        TensorNormOp<accreal, 1>{value},
                        ReduceMax<accreal>{},
                        thrust::identity<accreal>{},
                        scalar_cast<accreal>(0),
                        dimension, keepdim);
  } else {
    THC_reduceDim<real>(state, self, src,
                        TensorNormOp<accreal, -1>{value},
                        ReduceAdd<accreal>{},
                        ReducePow<accreal>{THCNumerics<accreal>::cinv(value)},
                        scalar_cast<accreal>(0),
                        dimension, keepdim);
  }

  THCudaCheck(cudaGetLastError());
}

THC_API accreal
THCTensor_(normall)(THCState *state, THCTensor *self, real _value)
{
  const accreal value = scalar_cast<accreal>(_value);
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal result;

  if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(0))) {
    THC_reduceAll<real>(state, self,
                        TensorNonZeroOp<accreal>{},
                        ReduceAdd<accreal>{},
                        scalar_cast<accreal>(0),
                        &result, 0);
  } else if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(1))) {
    THC_reduceAll<real>(state, self,
                        TensorNormOp<accreal, 1>{value},
                        ReduceAdd<accreal>{},
                        scalar_cast<accreal>(0),
                        &result, 0);
  } else if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(2))) {
    THC_reduceAll<real>(state, self,
                        TensorNormOp<accreal, 2>{value},
                        ReduceAdd<accreal>{},
                        scalar_cast<accreal>(0),
                        &result, 0);
    result = THCNumerics<accreal>::sqrt(result);
  } else if (THCNumerics<accreal>::eq(value, scalar_cast<accreal>(INFINITY))) {
    THC_reduceAll<real>(state, self,
                        TensorNormOp<accreal, 1>{value},
                        ReduceMax<accreal>{},
                        scalar_cast<accreal>(0),
                        &result, 0);
  } else {
    THC_reduceAll<real>(state, self,
                        TensorNormOp<accreal, -1>{value},
                        ReduceAdd<accreal>{},
                        scalar_cast<accreal>(0),
                        &result, 0);
    result = THCNumerics<accreal>::pow(result, 
                                       THCNumerics<accreal>::cinv(value));
  }

  THCudaCheck(cudaGetLastError());
  return result;
}

accreal THCTensor_(dist)(THCState *state, THCTensor *self,
                         THCTensor *src, real _value)
{
  const accreal value = scalar_cast<accreal>(_value);
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 2, self, src));
  self = THCTensor_(newContiguous)(state, self);
  ptrdiff_t size = THCTensor_(nElement)(state, self);
  src = THCTensor_(newContiguous)(state, src);
  thrust::device_ptr<real> self_data(THCTensor_(data)(state, self));
  thrust::device_ptr<real> src_data(THCTensor_(data)(state, src));

  THCThrustAllocator thrustAlloc(state);
  accreal result = thrust::inner_product(
#if CUDA_VERSION >= 7000
    thrust::cuda::par(thrustAlloc).on(THCState_getCurrentStream(state)),
#endif
    self_data, self_data+size, src_data, scalar_cast<accreal>(0),
    thrust::plus<accreal>(),
    ThrustTensorDistOp<real, accreal>(value));

  THCTensor_(free)(state, src);
  THCTensor_(free)(state, self);

  return THCNumerics<accreal>::pow(result, THCNumerics<accreal>::cinv(value));
}

#endif

THC_API accreal
THCTensor_(sumall)(THCState *state, THCTensor *self) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal val;
  if (!THC_reduceAll<real>(state, self,
                           thrust::identity<accreal>{},
                           ReduceAdd<accreal>{},
                           scalar_cast<accreal>(0),
                           &val, 0)) {
    THArgCheck(false, 1, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
  return val;
}

THC_API accreal
THCTensor_(prodall)(THCState *state, THCTensor *self) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal val;
  if (!THC_reduceAll<real>(state, self,
                           thrust::identity<accreal>{},
                           ReduceMultiply<accreal>{},
                           scalar_cast<accreal>(1),
                           &val, 0)) {
    THArgCheck(false, 1, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
  return val;
}

THC_API accreal
THCTensor_(meanall)(THCState *state, THCTensor *self)
{
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  return THCTensor_(sumall)(state, self)/THCTensor_(nElement)(state, self);
}

THC_API real
THCTensor_(minall)(THCState *state, THCTensor *self) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal val;
  if (!THC_reduceAll<real>(state, self,
                           thrust::identity<accreal>{},
                           ReduceMin<accreal>{},
                           THCNumerics<accreal>::max(), &val, 0)) {
    THArgCheck(false, 1, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
  return scalar_cast<real>(val);
}

THC_API real
THCTensor_(maxall)(THCState *state, THCTensor *self) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));
  accreal val;
  if (!THC_reduceAll<real>(state, self,
                           thrust::identity<accreal>{},
                           ReduceMax<accreal>{},
                           THCNumerics<accreal>::min(), &val, 0)) {
    THArgCheck(false, 1, CUTORCH_DIM_WARNING);
  }

  THCudaCheck(cudaGetLastError());
  return scalar_cast<real>(val);
}

THC_API real
THCTensor_(medianall)(THCState *state, THCTensor *self) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));

  real val;
  ptrdiff_t nelem, k;

  nelem = THCTensor_(nElement)(state, self);
  k = (nelem-1) >> 1;

  THCTensor *view = THCTensor_(newView)(state, self, {nelem});

  THCTensor *sorted = THCTensor_(new)(state);
  THCudaLongTensor *indices = THCudaLongTensor_new(state);

  THCTensor_(sort)(state, sorted, indices, view, 0, 0);

  val = THCTensor_(get1d)(state, sorted, k);

  THCTensor_(free)(state, view);
  THCTensor_(free)(state, sorted);
  THCudaLongTensor_free(state, indices);

  THCudaCheck(cudaGetLastError());

  return val;
}

THC_API void
THCTensor_(median)(THCState *state,
                   THCTensor *values,
                   THCudaLongTensor *indices,
                   THCTensor *self,
                   int dimension,
                   int keepdim) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 1, self));

  int64_t t_size_dim, k;

  t_size_dim = THCTensor_(size)(state, self, dimension);

  k = (t_size_dim-1) >> 1;

  THCTensor *sorted = THCTensor_(new)(state);
  THCudaLongTensor *sorted_indices = THCudaLongTensor_new(state);

  THCTensor_(sort)(state, sorted, sorted_indices, self, dimension, 0);

  THCTensor *newValues = THCTensor_(newNarrow)(state, sorted, dimension, k, 1);
  THCudaLongTensor *newIndices = THCudaLongTensor_newNarrow(state, sorted_indices, dimension, k, 1);

  THCTensor_(free)(state, sorted);
  THCudaLongTensor_free(state, sorted_indices);

  if (!keepdim) {
    THCTensor_(squeeze1d)(state, newValues, newValues, dimension);
    THCudaLongTensor_squeeze1d(state, newIndices, newIndices, dimension);
  }

  THCTensor_(resizeAs)(state, values, newValues);
  THCudaLongTensor_resizeAs(state, indices, newIndices);
  THCTensor_(copy)(state, values, newValues);
  THCudaLongTensor_copy(state, indices, newIndices);

  THCTensor_(free)(state, newValues);
  THCudaLongTensor_free(state, newIndices);

  THCudaCheck(cudaGetLastError());
}

THC_API void
THCTensor_(max)(THCState *state,
                THCTensor *values,
                THCudaLongTensor *indices,
                THCTensor *src,
                int dimension,
                int keepdim) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 3, values, indices, src));

  thrust::pair<real, int64_t>
    init =
    thrust::make_pair<real, int64_t>(
      THCNumerics<real>::min(), 0);

  return THC_reduceDimIndex<real, int64_t>(
    state, values, indices, src, dimension, keepdim, init,
    MaxValuePair<real, int64_t>());
}

THC_API void
THCTensor_(min)(THCState *state,
                THCTensor *values,
                THCudaLongTensor *indices,
                THCTensor *src,
                int dimension,
                int keepdim) {
  THCAssertSameGPU(THCTensor_(checkGPU)(state, 3, values, indices, src));

  thrust::pair<real, int64_t>
    init =
    thrust::make_pair<real, int64_t>(
      THCNumerics<real>::max(), 0);

  return THC_reduceDimIndex<real, int64_t>(
    state, values, indices, src, dimension, keepdim, init,
    MinValuePair<real, int64_t>());
}

#endif
